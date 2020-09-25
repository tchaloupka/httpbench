module magicrb;

import common;
import core.exception : onOutOfMemoryError;
import std.math : isPowerOf2;

shared static this()
{
    version (Windows)
    {
        import core.sys.windows.windows : SYSTEM_INFO, GetSystemInfo;

        SYSTEM_INFO info;
        GetSystemInfo(&info);

        pageSize = info.dwPageSize;
        allocationGranularity = info.dwAllocationGranularity;
    }
    else version (Posix)
    {
        import core.sys.posix.unistd : _SC_PAGESIZE, sysconf;
        pageSize = cast(size_t)sysconf(_SC_PAGESIZE);
    }
    else static assert(0, "Unsupported platform.");
}

private
{
    static immutable size_t pageSize;
    version (Windows) static immutable size_t allocationGranularity;

    version (Posix)
    {
        void* map(size_t fullSize) nothrow @nogc @trusted
        {
            import std.algorithm.mutation : copy;
            import std.algorithm.comparison : max, min;
            import core.sys.posix.unistd;
            version (Posix) import core.sys.posix.sys.mman;
            version (FreeBSD) import core.sys.freebsd.sys.mman : MAP_FIXED, MAP_SHARED, MAP_ANON;
            version (NetBSD) import core.sys.netbsd.sys.mman : MAP_FIXED, MAP_SHARED, MAP_ANON;
            version (linux) import core.sys.linux.sys.mman : MAP_FIXED, MAP_SHARED, MAP_ANON;
            version (OSX) import core.sys.darwin.sys.mman : MAP_FIXED, MAP_SHARED, MAP_ANON;
            import core.sys.posix.fcntl;

            // mmap space to reserve the address space. We won't actually wire this
            // to any memory until we open the shared memory and map it.
            auto addr = mmap(null, fullSize * 2, PROT_NONE, MAP_SHARED | MAP_ANON, -1, 0);
            if(addr == MAP_FAILED)
                return null;

            // attempt to make a name that won't conflict with other processes.
            // This is really sucky, but is required on posix systems, even though
            // we aren't really sharing memory.
            enum basename = "/ivisec_map_";
            char[basename.length + 8 + 1] shm_name = void;
            shm_name[0 .. basename.length] = basename;
            shm_name[basename.length .. $-1] = 'A';
            // get the process id
            uint pid = getpid();
            auto idx = basename.length;
            while(pid)
            {
                shm_name[idx++] = cast(char)('A' + (pid & 0x0f));
                pid >>= 4;
            }
            shm_name[$-1] = 0;

            import std.conv: octal;
            import std.exception;
            int shfd = -1;
            idx = 0;
            while(shfd < 0)
            {
                // try 4 times to make this happen, if it doesn't, give up and
                // return 0. This helps solve any possible race conditions with
                // other threads. It's not perfect, but it should work reasonably
                // well.
                if(idx++ > 4)
                {
                    munmap(addr, fullSize * 2);
                    return null;
                }
                shfd = shm_open(&shm_name[0], O_RDWR | O_CREAT | O_EXCL, octal!"600");
                // immediately remove the name link, we don't really want to share anything here.
                shm_unlink(&shm_name[0]);
            }

            // after this function, we don't need the file descriptor.
            scope(exit) close(shfd);

            // create enough memory to hold the entire buffer.
            if(ftruncate(shfd, fullSize) < 0)
            {
                munmap(addr, fullSize * 2);
                return null;
            }

            // map the shared memory into the reserved space twice, each half sees
            // the same memory.
            if(mmap(addr, fullSize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, shfd, 0) == MAP_FAILED)
            {
                munmap(addr, fullSize * 2);
                return null;
            }
            if(mmap(addr + fullSize, fullSize, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_FIXED, shfd, 0) == MAP_FAILED)
            {
                munmap(addr, fullSize * 2);
                return null;
            }

            return addr;
        }

        void unmap(void* addr, ulong size) nothrow @nogc @trusted
        {
            if (addr)
            {
                import core.sys.posix.sys.mman : munmap;
                if (munmap(addr, size * 2) == -1) assert(0, "failed to munmap");
            }
        }
    }
    else version (Windows)
    {
        import core.sys.windows.basetsd;
        import core.sys.windows.winbase;
        import core.sys.windows.winnt;
        import std.typecons : Tuple;

        alias MapRes = Tuple!(void*, "addr", HANDLE, "handle");

        MapRes map(size_t size) nothrow @nogc @trusted
        {
            assert(
                (size % allocationGranularity) == 0,
                nogcFormat!"Invalid size granularity: req=%s, gran=%s"(size, allocationGranularity));

            immutable allocSize = size * 2;

            HANDLE mmapHandle;
            void* addr;
            // Because we cannot use mmap to virtualy allocated memory we are using
            // VirtualAlloc only to find an address and then immediately free it
            // and mmap it. Because this cannot be done atomically we give it a try
            // 5 times which should be reasonably enough.
            auto rem = 5;
            while (rem--)
            {
                // find available memory block address
                addr = VirtualAlloc(null, allocSize, MEM_RESERVE, PAGE_NOACCESS);
                if (!addr) continue;
                VirtualFree(addr, 0, MEM_RELEASE);

                // prep mmap handle
                mmapHandle = CreateFileMappingA(
                    INVALID_HANDLE_VALUE, null, PAGE_READWRITE,
                    cast(ulong) size >> 32, size & 0xffffffffu, null);
                if (!mmapHandle)
                {
                    addr = null;
                    continue;
                }

                // map file to address space
                const void* bufPtr = MapViewOfFileEx(mmapHandle, FILE_MAP_ALL_ACCESS, 0, 0, size, addr);
                if (!bufPtr)
                {
                    addr = null;
                    CloseHandle(mmapHandle);
                    mmapHandle = null;
                    continue;
                }
                else if (bufPtr !is addr) assert(0, "Unexpected MapVievOfFileEx result");

                // map next view address space to the same file
                if (!MapViewOfFileEx(mmapHandle, FILE_MAP_ALL_ACCESS, 0, 0, size, addr + size))
                {
                    addr = null;
                    UnmapViewOfFile(bufPtr);
                    CloseHandle(mmapHandle);
                    mmapHandle = null;
                    continue;
                }

                break;
            }

            return MapRes(addr, mmapHandle);
        }

        void unmap(void* addr, ulong size) nothrow @nogc @trusted
        {
            if (addr)
            {
                UnmapViewOfFile(addr);
                UnmapViewOfFile(addr + size);
            }
        }
    }

    size_t mask(size_t val, size_t size) pure @safe nothrow @nogc
    {
        pragma(inline);
        return val & (size - 1);
    }
}

/**
 * Ring buffer is using OS mmap mechanism to avoid two copies when data wrap.
 * It also using mask principle which is simplifing the overall code.
 *
 * Params:
 *      T = Type of buffer array. Must be [isPowerOf2].
 */
struct RingBuffer(T) if (isPowerOf2(T.sizeof))
{
    @safe nothrow @nogc:

    private
    {
        version (Windows) HANDLE mmapHandle; // mmap handle
        T[] buffer;
        size_t head;
        size_t tail;
    }

    @disable this(this); // we can't copy RingBuffer because otherwise it will deallocate the memory

    /**
     * Tries to allocate two consecutive memory pages of the size (rounded up to either to allocation granularity or page size).
     *
     * Params: capacity = buffer size (round up to Windows: allocation granularity, Posix: page size).
     */
    bool alloc(size_t capacity) @trusted
    {
        assert(capacity > 0);
        assert(buffer is null, "Buffer is already allocated");

        version (Windows) size_t cap = allocationGranularity;
        else size_t cap = pageSize;

        while (cap < capacity * T.sizeof) cap *= 2;

        assert(isPowerOf2(cap));

        auto mapRes = map(cap);
        version (Windows) auto addr = mapRes.addr;
        else alias addr = mapRes;

        if (!addr) return false;
        version (Windows) mmapHandle = mapRes.handle;
        buffer = (cast(T*)addr)[0..cap/T.sizeof*2];

        return true;
    }

    /**
     * Frees allocated memory.
     */
    ~this() @nogc
    {
        if (buffer)
        {
            unmap(&buffer[0], capacity * T.sizeof);
            version (Windows)
            {
                assert(mmapHandle, "mmapHandle is already null");
                CloseHandle(mmapHandle);
            }
        }
    }

    /**
     * Reserves elements for writing, this is especially usefull when system functions are filling the buffer.
     *
     * Params: size = amount of elements to reserve.
     *
     * Returns: amount of elements actually reserved. 0 if failed.
     */
    size_t reserve(size_t size) @trusted
    {
        if (_expect(capacity == 0, false))
        {
            auto res = alloc(size);
            if (_expect(!res, false)) return 0;
            tail += size;
            return size;
        }

        if (_expect(avail < size, false))
        {
            auto newSize = capacity * 2;
            while (newSize < length + size) newSize *= 2; // multiply capacity until old data + requested size doesn't fit
            assert(isPowerOf2(newSize));

            auto mapRes = map(newSize * T.sizeof);
            version (Windows) auto addr = mapRes.addr;
            else alias addr = mapRes;
            if (_expect(!addr, false)) return 0;

            auto newBuffer = (cast(T*)addr)[0..newSize*2];
            if (length)
            {
                // copy data to new buffer
                import std.algorithm.mutation : copy;
                copy(data, newBuffer[0..length]);
                tail = length;
                head = 0;

                // unmap previous buffer
                unmap(&buffer[0], capacity * T.sizeof);
                version (Windows) CloseHandle(mmapHandle);
            }

            buffer = newBuffer;
            version (Windows) mmapHandle = mapRes.handle;
        }

        tail += size;
        return size;
    }

    /// Returns: Slice of valid data in the buffer.
    inout(T)[] data() inout pure
    {
        pragma(inline);
        if (_expect(empty, false)) return null;
        immutable idx = mask(head, capacity);
        return buffer[idx..idx + length];
    }

    /// `InputRange` property to access first element in the buffer
    ref T front() return
    {
        assert(!empty, "Buffer is empty");
        return this.data[0];
    }

    /**
     * Releases elements from the front of the buffer so they can be reused for writing.
     *
     * Params:
     *      size = amount of elements to release.
     */
    void popFront(size_t size = 1) pure
    {
        assert(size <= length, "Can't pop more than is available");
        head += size;
    }

    /**
     * Releases elements from the back of the buffer so they can be reused for writing.
     *
     * Params: size = amount of elements to release.
     */
    void popBack(size_t size = 1) pure
    {
        assert(size <= length, "Can't pop more than is available");
        tail -= size;
    }

    // drop aliases
    alias drop = popFront;
    alias dropFront = popFront;
    alias dropBack = popBack;

    /// Clears buffer
    void clear() pure
    {
        if (_expect(!empty, true)) popFront(length);
    }

    /// Support to directly append data to the buffer
    void put(T val)
    {
        import std.algorithm : move;
        if (_expect(reserve(1) < 1, false)) onOutOfMemoryError();
        val.move(buffer[mask(tail - 1, capacity)]);
    }

    /// ditto
    void put(T[] val)
    {
        import std.algorithm : moveAll;
        if (_expect(reserve(val.length) < val.length, false)) onOutOfMemoryError();
        immutable idx = mask(tail - val.length, capacity);
        buffer[idx .. idx + val.length] = val[];
    }

    /// ditto
    alias opOpAssign(string op : "~") = put;

    /// Slicing support for the internal buffer data
    alias opSlice = data;

    /// ditto
    inout(T)[] opSlice(size_t start, size_t end) inout pure
    {
        assert(start <= length && end <= length, "Index out of bounds"); // empty slice on end is fine too
        assert(start <= end, "Invalid slice indexes");
        return this.data[start .. end];
    }

    /// Indexed access to the buffer data
    @property ref T opIndex(size_t idx) return pure
    {
        assert(idx < length, "Index out of bounds");
        return buffer[mask(head, capacity)+idx];
    }

    /// opDollar implementation
    alias length opDollar;

    /// Returns: True if buffer is empty.
    bool empty() const pure
    {
        pragma(inline);
        return head == tail;
    }

    /// Returns: Number of available elements in the buffer.
    size_t avail() const pure
    {
        pragma(inline);
        return capacity - length;
    }

    /// Returns: Capacity of the buffer.
    size_t capacity() const pure
    {
        pragma(inline);
        return buffer.length / 2;
    }

    /// Returns: True when buffer is full.
    bool full() const pure
    {
        pragma(inline);
        return length == capacity;
    }

    /// Returns: Length of the elements in the buffer.
    size_t length() const pure
    {
        pragma(inline);
        return tail - head;
    }
}

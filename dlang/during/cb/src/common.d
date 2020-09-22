module common;

import during;

alias OnCompletionCB = int function(ref Uring io, ref IOContext ctx, int res) nothrow @nogc;

struct IOContext
{
    OnCompletionCB onCompletion;    /// Completation callback
    int fd;                         /// File Descriptor
    ubyte[] buffer;                 /// read/write buffer slice
    void* data;                     /// custom user data
}

version(LDC) public import ldc.intrinsics: _expect = llvm_expect;
else
{
    T _expect(T)(T val, T expected_val) if (__traits(isIntegral, T))
    {
        pragma(inline, true);
        return val;
    }
}

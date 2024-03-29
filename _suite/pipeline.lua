init = function(args)
    local r = {}
    local depth = tonumber(args[1]) or 1
    for i=1,depth do
        r[i] = wrk.format()
    end
    req = table.concat(r)
end

request = function()
    return req
end

done = function(summary, latency, requests)
    io.write("Custom stats: ")
    io.write(string.format("%d", latency.min))
    for _, p in pairs({ 25, 50, 75, 99 }) do
        n = latency:percentile(p)
        io.write(string.format(" %d", n))
    end
    io.write(string.format(" %d\n", latency.max))
end

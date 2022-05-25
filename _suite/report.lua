done = function(summary, latency, requests)
    io.write("Custom stats: ")
    io.write(string.format("%d", latency.min))
    for _, p in pairs({ 25, 50, 75, 99 }) do
        n = latency:percentile(p)
        io.write(string.format(" %d", n))
    end
    io.write(string.format(" %d\n", latency.max))
end

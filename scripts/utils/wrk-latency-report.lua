-- Optional wrk Lua: aggregate latency report (extend for per-second buckets as needed)
done = function(summary, latency, requests)
  io.write("------------------------------\n")
  for _, p in pairs({ 50, 75, 90, 99, 99.9 }) do
    io.write(string.format("%g%%: %.2fms\n", p, latency:percentile(p) / 1000))
  end
end

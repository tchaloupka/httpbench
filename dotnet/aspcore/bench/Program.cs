// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System.Runtime.InteropServices;

namespace PlatformBenchmarks;

public class Program
{
    public static string[] Args;

    public static async Task Main(string[] args)
    {
        Args = args;

        Console.WriteLine(BenchmarkApplication.ApplicationName);
        Console.WriteLine(BenchmarkApplication.Paths.Plaintext);
        DateHeader.SyncDateTimer();

        var host = BuildWebHost(args);
        var config = (IConfiguration)host.Services.GetService(typeof(IConfiguration));
        await host.RunAsync();
    }

    public static IWebHost BuildWebHost(string[] args)
    {
        var config = new ConfigurationBuilder()
            .AddJsonFile("appsettings.json")
            .AddEnvironmentVariables()
            .AddEnvironmentVariables(prefix: "ASPNETCORE_")
            .AddCommandLine(args)
            .Build();

        var host = new WebHostBuilder()
            .UseBenchmarksConfiguration(config)
            .UseKestrel((context, options) =>
            {
                var endPoint = context.Configuration.CreateIPEndPoint();

                options.Listen(endPoint, builder =>
                {
                    builder.UseHttpApplication<BenchmarkApplication>();
                });
            })
            .UseStartup<Startup>()
            .Build();

        return host;
    }
}

// Copyright (c) .NET Foundation. All rights reserved.
// Licensed under the Apache License, Version 2.0. See License.txt in the project root for license information.

using System;
using System.Buffers.Text;
using System.IO.Pipelines;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;

using Microsoft.AspNetCore.Server.Kestrel.Core.Internal.Http;

namespace PlatformBenchmarks;

public partial class BenchmarkApplication
{
    private readonly static AsciiString _applicationName = "Kestrel Platform-Level Application";
    public static AsciiString ApplicationName => _applicationName;

    private readonly static AsciiString _crlf = "\r\n";
    private readonly static AsciiString _eoh = "\r\n\r\n"; // End Of Headers
    private readonly static AsciiString _http11OK = "HTTP/1.1 200 OK\r\n";
    private readonly static AsciiString _http11NotFound = "HTTP/1.1 404 Not Found\r\n";
    private readonly static AsciiString _headerServer = "Server: K";
    private readonly static AsciiString _headerContentLength = "Content-Length: ";
    private readonly static AsciiString _headerContentLengthZero = "Content-Length: 0";
    private readonly static AsciiString _headerContentTypeText = "Content-Type: text/plain";
    private readonly static AsciiString _headerContentTypeJson = "Content-Type: application/json";
    private readonly static AsciiString _headerContentTypeHtml = "Content-Type: text/html; charset=UTF-8";

    private readonly static AsciiString _padHeader = "X-Test: 01234567890123456789012345012345678901234567890123456789";

    private readonly static AsciiString _plainTextBody = "Hello, World!";

    private static readonly JsonSerializerOptions SerializerOptions = new JsonSerializerOptions();
    private readonly static AsciiString _contentLengthGap = new string(' ', 4);

    public static class Paths
    {
        public readonly static AsciiString Plaintext = "/";
    }

    private RequestType _requestType;
    private int _queries;

    public void OnStartLine(HttpVersionAndMethod versionAndMethod, TargetOffsetPathLength targetPath, Span<byte> startLine)
    {
        _requestType = versionAndMethod.Method == Microsoft.AspNetCore.Server.Kestrel.Core.Internal.Http.HttpMethod.Get ? GetRequestType(startLine.Slice(targetPath.Offset, targetPath.Length), ref _queries) : RequestType.NotRecognized;
    }

    private RequestType GetRequestType(ReadOnlySpan<byte> path, ref int queries)
    {
        if (path.SequenceEqual(Paths.Plaintext))
        {
            return RequestType.PlainText;
        }
        return RequestType.NotRecognized;
    }


    private void ProcessRequest(ref BufferWriter<WriterAdapter> writer)
    {
        if (_requestType == RequestType.PlainText)
        {
            PlainText(ref writer);
        }
        else
        {
            Default(ref writer);
        }
    }
    private readonly static AsciiString _defaultPreamble =
        _http11NotFound +
        _headerServer + _crlf +
        _headerContentTypeText + _crlf +
        _headerContentLengthZero;

    private static void Default(ref BufferWriter<WriterAdapter> writer)
    {
        writer.Write(_defaultPreamble);

        // Date header
        writer.Write(DateHeader.HeaderBytes);
    }

    private enum RequestType
    {
        NotRecognized,
        PlainText,
        Json,
        Fortunes,
        SingleQuery,
        Caching,
        Updates,
        MultipleQueries
    }
}

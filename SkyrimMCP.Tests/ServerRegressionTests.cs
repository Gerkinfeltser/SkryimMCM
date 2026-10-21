using System.IO.Pipelines;
using System.IO.Pipes;
using System.Text.Json;
using System.Text.Json.Nodes;
using ModelContextProtocol.Client;
using ModelContextProtocol.Protocol;
using ModelContextProtocol.Server;
using SkyrimMCP;
using SkyrimMCP.Tools;
using Xunit;

namespace SkyrimMCP.Tests;

/// <summary>
/// Calls real tools through an in-memory MCP client/server, so results pass through the SDK like a real caller sees them.
/// The pipe uses a private name and a fake plugin, so a running game is never contacted.
/// </summary>
public class ServerRegressionTests
{
    // 7.1: paged tools keep the plugin's other top-level fields
    [Fact]
    public async Task PagedResponseKeepsExtraTopLevelFields()
    {
        var plugin = """{"success":true,"data":{"perks":[{"name":"A"},{"name":"B"},{"name":"C"}],"complete":false,"incompleteReason":"VR runtime-added perk layout is not validated","refId":"00000014","name":"Prisoner"}}""";
        var result = await CallToolAsync("get_perks", plugin, new() { ["page"] = 1, ["pageSize"] = 2 });

        Assert.NotEqual(true, result.IsError);
        var json = JsonNode.Parse(((TextContentBlock)result.Content[0]).Text)!;
        Assert.False(json["complete"]!.GetValue<bool>());
        Assert.Equal("VR runtime-added perk layout is not validated", json["incompleteReason"]!.GetValue<string>());
        Assert.Equal("00000014", json["refId"]!.GetValue<string>());
        Assert.Equal("Prisoner", json["name"]!.GetValue<string>());
        Assert.Null(json["perks"]);
        Assert.Equal(2, json["items"]!.AsArray().Count);
        Assert.Equal(3, json["totalItems"]!.GetValue<int>());
        Assert.True(json["hasMore"]!.GetValue<bool>());
    }

    // 7.2: a plugin {"error": ...} reaches the MCP caller with its message
    [Fact]
    public async Task PluginErrorReachesCallerWithMessage()
    {
        var plugin = """{"success":false,"error":"God Mode is unavailable in VR: engine binding is not validated"}""";
        var result = await CallToolAsync("toggle_god_mode", plugin, new());

        Assert.True(result.IsError);
        Assert.Contains("God Mode is unavailable in VR: engine binding is not validated", ((TextContentBlock)result.Content[0]).Text);
    }

    private static async Task<CallToolResult> CallToolAsync(string tool, string pluginResponse, Dictionary<string, object?> args)
    {
        var pipeName = $"SkyrimMCP-test-{Guid.NewGuid():N}";
        using var pipe = new PipeClient(pipeName);
        var fakePlugin = FakePluginAsync(pipeName, pluginResponse);

        var clientToServer = new Pipe();
        var serverToClient = new Pipe();
        var options = new McpServerOptions { ToolCollection = [] };
        foreach (var type in new[] { typeof(PlayerTools) })
        {
            var target = Activator.CreateInstance(type, (IPipeClient)pipe)!;
            foreach (var method in type.GetMethods().Where(m => m.IsDefined(typeof(McpServerToolAttribute), false)))
                options.ToolCollection.Add(McpServerTool.Create(method, target));
        }

        await using var server = McpServer.Create(
            new StreamServerTransport(clientToServer.Reader.AsStream(), serverToClient.Writer.AsStream()), options);
        using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(30));
        var serverTask = server.RunAsync(cts.Token);

        await using var client = await McpClient.CreateAsync(
            new StreamClientTransport(clientToServer.Writer.AsStream(), serverToClient.Reader.AsStream()),
            cancellationToken: cts.Token);
        var result = await client.CallToolAsync(tool, args, cancellationToken: cts.Token);

        await fakePlugin;
        return result;
    }

    // Answers one request with a canned response, like the SKSE plugin's pipe server
    private static async Task FakePluginAsync(string pipeName, string response)
    {
        await using var server = new NamedPipeServerStream(pipeName, PipeDirection.InOut, 1, PipeTransmissionMode.Byte, System.IO.Pipes.PipeOptions.Asynchronous);
        await server.WaitForConnectionAsync();
        using var reader = new StreamReader(server);
        await using var writer = new StreamWriter(server) { AutoFlush = true };
        await reader.ReadLineAsync();
        await writer.WriteLineAsync(response);
    }
}

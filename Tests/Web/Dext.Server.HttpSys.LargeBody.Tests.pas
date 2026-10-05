unit Dext.Server.HttpSys.LargeBody.Tests;

interface

uses
  Dext.Testing.Attributes;

type
  /// <summary>
  ///   A response body made of more segments than one http.sys call accepts
  ///   (9,999 entity chunks) must still reach the client complete. Each test
  ///   starts a real HTTP.sys listener on 127.0.0.1, writes the body in 4 KB
  ///   pieces (one writer segment each, no compression) and downloads it with
  ///   THTTPClient, checking the status, the length and the content of every
  ///   piece.
  /// </summary>
  [TestFixture('HTTP.sys - bodies with more segments than one call accepts')]
  THttpSysLargeBodyTests = class
  private
    procedure SendAndCheck(ASegments: Integer);
  public
    [Test('Should send a body of 9,999 segments (the per-call limit)')]
    procedure TestBodyAtTheLimit;
    [Test('Should send a body of 10,000 segments')]
    procedure TestBodyOf10000Segments;
    [Test('Should send a body of 25,000 segments')]
    procedure TestBodyOf25000Segments;
  end;

implementation

uses
  System.Classes,
  System.SysUtils,
  System.Net.HttpClient,
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Server.Engine.Types;

const
  SegmentSize = 4096;
  TestPort = 9219;
  // Long enough for 100 MB on loopback; without the fix the client waits
  // this long and the test fails instead of hanging.
  ClientTimeoutMs = 30000;

{ THttpSysLargeBodyTests }

procedure THttpSysLargeBodyTests.SendAndCheck(ASegments: Integer);
var
  App: IWebApplication;
  Options: TServerEngineOptions;
  Client: THTTPClient;
  Body: TMemoryStream;
  // Qualified: Dext.Web.Interfaces has an IHttpResponse too.
  Resp: System.Net.HttpClient.IHTTPResponse;
  I, Wrong: Integer;
  P: PByte;
begin
  App := WebApplication;
  try
    App.GetApplicationBuilder.Use(
      procedure(Ctx: IHttpContext; Next: TRequestDelegate)
      var
        Piece: TBytes;
        K: Integer;
      begin
        if Ctx.Request.Path = '/big' then
        begin
          for K := 0 to ASegments - 1 do
          begin
            // A new buffer per piece: the writer may keep a reference to it.
            Piece := nil;
            SetLength(Piece, SegmentSize);
            FillChar(Piece[0], SegmentSize, Byte(K mod 251));
            Ctx.Response.Write(Piece);
          end;
        end
        else
          Next(Ctx);
      end);
    Options := TServerEngineOptions.Default.WithBindAddress('127.0.0.1');
    App.UseNativeServer(Options);
    App.Start(TestPort);
    try
      Client := THTTPClient.Create;
      Body := TMemoryStream.Create;
      try
        Client.ConnectionTimeout := ClientTimeoutMs;
        Client.ResponseTimeout := ClientTimeoutMs;
        Resp := Client.Get('http://127.0.0.1:' + IntToStr(TestPort) + '/big',
          Body);
        Should(Resp.StatusCode).Be(200);
        Should(Integer(Body.Size)).Be(ASegments * SegmentSize);
        // Every piece in its place: merged segments must keep their order.
        Wrong := 0;
        P := Body.Memory;
        for I := 0 to ASegments - 1 do
        begin
          if (P[I * SegmentSize] <> Byte(I mod 251)) or
            (P[I * SegmentSize + SegmentSize - 1] <> Byte(I mod 251)) then
            Inc(Wrong);
        end;
        Should(Wrong).Be(0);
      finally
        Body.Free;
        Client.Free;
      end;
    finally
      App.Stop;
    end;
  finally
    App := nil;
  end;
end;

procedure THttpSysLargeBodyTests.TestBodyAtTheLimit;
begin
  SendAndCheck(9999);
end;

procedure THttpSysLargeBodyTests.TestBodyOf10000Segments;
begin
  SendAndCheck(10000);
end;

procedure THttpSysLargeBodyTests.TestBodyOf25000Segments;
begin
  SendAndCheck(25000);
end;

end.

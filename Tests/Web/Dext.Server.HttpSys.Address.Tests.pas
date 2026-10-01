unit Dext.Server.HttpSys.Address.Tests;

interface

uses
  System.Classes,
  System.SysUtils,
  Winapi.Winsock2,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Net.RestClient,
  Dext.Server.Engine.Interfaces,
  Dext.Server.Engine.Types,
  Dext.Server.HttpSys.Api,
  Dext.Server.HttpSys;

type
  [TestFixture('HTTP.sys - remote and local address of the connection')]
  THttpSysAddressTests = class
  public
    // --- TDextHttpSysConnection.Init, on a mocked HTTP_REQUEST.Address -------
    [Test('Should read remote address, remote port and local port from IPv4 sockaddrs')]
    procedure TestReadsIPv4Addresses;

    [Test('Should read remote address, remote port and local port from IPv6 sockaddrs')]
    procedure TestReadsIPv6Addresses;

    [Test('Should leave the values empty when http.sys provides no sockaddr')]
    procedure TestNilAddressesLeaveValuesEmpty;

    [Test('Should ignore a sockaddr of an unknown address family')]
    procedure TestUnknownFamilyIsIgnored;

    // --- end to end, through a real http.sys listener ----------------------
    [Test('Should expose the client address as Request.RemoteIpAddress on HTTP.sys')]
    procedure TestRealHttpSysRemoteIpAddress;
  end;

implementation

function MakeIPv4(const AOctets: array of Byte; APort: Word): sockaddr_in;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.sin_family := AF_INET;
  Result.sin_port := htons(APort);
  Move(AOctets[0], Result.sin_addr, 4);
end;

function MakeIPv6(const ABytes: array of Byte; APort: Word): SOCKADDR_IN6;
begin
  FillChar(Result, SizeOf(Result), 0);
  Result.sin6_family := AF_INET6;
  Result.sin6_port := htons(APort);
  Move(ABytes[0], Result.sin6_addr, 16);
end;

function NewConnection(const ARequest: HTTP_REQUEST): IDextServerConnection;
begin
  Result := TDextHttpSysConnection.Create(nil, ARequest, 0);
end;

{ THttpSysAddressTests }

procedure THttpSysAddressTests.TestReadsIPv4Addresses;
var
  Request: HTTP_REQUEST;
  Remote: sockaddr_in;
  Local: sockaddr_in;
  Conn: IDextServerConnection;
begin
  FillChar(Request, SizeOf(Request), 0);
  Remote := MakeIPv4([192, 168, 1, 20], 51234);
  Local := MakeIPv4([10, 0, 0, 5], 443);
  Request.Address.pRemoteAddress := @Remote;
  Request.Address.pLocalAddress := @Local;

  Conn := NewConnection(Request);

  Should(Conn.RemoteAddress).Be('192.168.1.20');
  Should(Integer(Conn.RemotePort)).Be(51234)
    .Because('the port arrives in network byte order');
  Should(Integer(Conn.LocalPort)).Be(443)
    .Because('the local port is the one the request came in on, not a fixed 80');
end;

procedure THttpSysAddressTests.TestReadsIPv6Addresses;
var
  Request: HTTP_REQUEST;
  Remote: SOCKADDR_IN6;
  Local: SOCKADDR_IN6;
  Conn: IDextServerConnection;
begin
  FillChar(Request, SizeOf(Request), 0);
  // 2001:db8::1
  Remote := MakeIPv6([$20, $01, $0D, $B8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], 60000);
  // ::1
  Local := MakeIPv6([0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1], 8443);
  Request.Address.pRemoteAddress := @Remote;
  Request.Address.pLocalAddress := @Local;

  Conn := NewConnection(Request);

  Should(Conn.RemoteAddress).Be('2001:db8::1');
  Should(Integer(Conn.RemotePort)).Be(60000);
  Should(Integer(Conn.LocalPort)).Be(8443);
end;

procedure THttpSysAddressTests.TestNilAddressesLeaveValuesEmpty;
var
  Request: HTTP_REQUEST;
  Conn: IDextServerConnection;
begin
  FillChar(Request, SizeOf(Request), 0);

  Conn := NewConnection(Request);

  Should(Conn.RemoteAddress).BeEmpty;
  Should(Integer(Conn.RemotePort)).Be(0);
  Should(Integer(Conn.LocalPort)).Be(0);
end;

procedure THttpSysAddressTests.TestUnknownFamilyIsIgnored;
var
  Request: HTTP_REQUEST;
  Remote: sockaddr_in;
  Conn: IDextServerConnection;
begin
  FillChar(Request, SizeOf(Request), 0);
  Remote := MakeIPv4([192, 168, 1, 20], 51234);
  Remote.sin_family := AF_UNIX;
  Request.Address.pRemoteAddress := @Remote;

  Conn := NewConnection(Request);

  Should(Conn.RemoteAddress).BeEmpty;
  Should(Integer(Conn.RemotePort)).Be(0);
end;

procedure THttpSysAddressTests.TestRealHttpSysRemoteIpAddress;
var
  App: IWebApplication;
  Resp: IRestResponse;
  Options: TServerEngineOptions;
begin
  App := WebApplication;
  try
    App.GetApplicationBuilder.Use(
      procedure(Ctx: IHttpContext; Next: TRequestDelegate)
      begin
        if Ctx.Request.Path = '/whoami' then
          Ctx.Response.Write('Ip=' + Ctx.Request.RemoteIpAddress)
        else
          Next(Ctx);
      end);
    Options := TServerEngineOptions.Default.WithBindAddress('127.0.0.1');
    App.UseNativeServer(Options);
    App.Start(9096);
    try
      Resp := RestClient('http://127.0.0.1:' + App.Port.ToString)
        .Get('/whoami')
        .Await;

      Should(Resp.StatusCode).Be(200);
      Should(Resp.ContentString).Be('Ip=127.0.0.1');
    finally
      App.Stop;
    end;
  finally
    App := nil;
  end;
end;

end.

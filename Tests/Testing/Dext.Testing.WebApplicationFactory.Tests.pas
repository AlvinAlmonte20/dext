unit Dext.Testing.WebApplicationFactory.Tests;

interface

uses
  Dext.Testing,
  Dext.Testing.WebApplicationFactory,
  Dext.Web,
  Dext.Web.Interfaces,
  Dext.Web.Results,
  System.SysUtils;

type
  [TestFixture]
  TWebApplicationFactoryTests = class
  public
    [Test]
    procedure CreateClient_Get_Dispatches_InProcess_Without_Tcp;
    [Test]
    procedure WithConfigure_MapControllers_Keeps_Application_Alive;
  end;

implementation

procedure TWebApplicationFactoryTests.CreateClient_Get_Dispatches_InProcess_Without_Tcp;
var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
  Response: IDextTestHttpResponse;
begin
  Factory := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        App.Builder.MapGet('/api/ping',
          procedure(Ctx: IHttpContext)
          begin
            Results.Ok('pong').Execute(Ctx);
          end);
      end);
  try
    Client := Factory.CreateClient;
    Response := Client.Get('/api/ping');
    Should(Response.StatusCode).Be(200);
    Should(Response.Body).Contain('pong');
  finally
    Factory.Free;
  end;
end;

procedure TWebApplicationFactoryTests.WithConfigure_MapControllers_Keeps_Application_Alive;
var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
  Response: IDextTestHttpResponse;
begin
  Factory := TDextApplicationFactory<TObject>.Create
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        App.Builder.MapGet('/api/ping',
          procedure(Ctx: IHttpContext)
          begin
            Results.Ok('pong').Execute(Ctx);
          end);
        // MapControllers returns the application as IWebApplication: the
        // temporary interface must not free it.
        App.MapControllers;
      end);
  try
    Client := Factory.CreateClient;
    Response := Client.Get('/api/ping');
    Should(Response.StatusCode).Be(200);
    Should(Response.Body).Contain('pong');
  finally
    Factory.Free;
  end;
end;

end.

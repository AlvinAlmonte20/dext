{***************************************************************************}
{                                                                           }
{           Dext Framework                                                  }
{                                                                           }
{           Copyright (C) 2025 Cesar Romero & Dext Contributors             }
{                                                                           }
{           Licensed under the Apache License, Version 2.0 (the "License"); }
{           you may not use this file except in compliance with the License.}
{           You may obtain a copy of the License at                         }
{                                                                           }
{               http://www.apache.org/licenses/LICENSE-2.0                  }
{                                                                           }
{           Unless required by applicable law or agreed to in writing,      }
{           software distributed under the License is distributed on an     }
{           "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND,    }
{           either express or implied. See the License for the specific     }
{           language governing permissions and limitations under the        }
{           License.                                                        }
{                                                                           }
{***************************************************************************}
unit TRestClient_IntoBody_Tests;

interface

uses
  System.SysUtils,
  System.Classes,
  Dext.Testing,
  Dext.Testing.Fluent,
  Dext.Net.RestClient,
  Dext.Web,
  Dext.Web.Interfaces;

type
  /// <summary>
  ///   PostInto / PutInto / PatchInto / QueryInto on the TRestClient facade
  ///   take a request body, against a real in-process server that echoes the
  ///   verb, the Content-Type and the body it received.
  /// </summary>
  [TestFixture('TRestClient *Into with a request body')]
  TRestClientIntoBodyTests = class
  private
    FHost: IWebHost;
    FBaseUrl: string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;

    [Test]
    procedure PostInto_SendsTheBody;
    [Test]
    procedure PutInto_SendsTheBody;
    [Test]
    procedure PatchInto_SendsTheBody;
    [Test]
    procedure QueryInto_SendsTheBody_WithTheClientContentType;
    [Test]
    procedure WithoutABody_WorksAsBefore;
    [Test]
    procedure ExecuteIntoAsync_IsOnTheFacade;
    [Test]
    procedure OwnsBody_TheClientFreesIt;
    [Test]
    procedure NotOwned_TheCallerKeepsIt;
    [Test]
    procedure ErrorStatus_LeavesTheTargetUntouched;
    [Test]
    procedure SameStreamForBodyAndTarget_IsRefused;
    [Test]
    procedure NilTarget_FreesAnOwnedBody;
    [Test]
    procedure ExecuteIntoAsync_NilTarget_FreesAnOwnedBody;
    [Test]
    procedure NilTargetAndNilBody_IsTheNilTargetError;
  end;

implementation

type
  /// A body that says when it is freed.
  TWatchedStream = class(TStringStream)
  public
    class var Freed: Boolean;
    destructor Destroy; override;
  end;

destructor TWatchedStream.Destroy;
begin
  Freed := True;
  inherited;
end;

function TextOf(AStream: TStream): string;
var
  Bytes: TBytes;
begin
  SetLength(Bytes, AStream.Size);
  AStream.Position := 0;
  if AStream.Size > 0 then
    AStream.ReadBuffer(Bytes[0], AStream.Size);
  Result := TEncoding.UTF8.GetString(Bytes);
end;

function Body(const AText: string): TStringStream;
begin
  Result := TStringStream.Create(AText, TEncoding.UTF8);
end;

procedure Echo(Ctx: IHttpContext);
var
  Received: string;
begin
  Received := '';
  if Ctx.Request.Body <> nil then
    Received := TextOf(Ctx.Request.Body);
  Ctx.Response.SetContentType('text/plain; charset=utf-8');
  Ctx.Response.Write(TEncoding.UTF8.GetBytes(Ctx.Request.Method + '|' +
    Ctx.Request.GetHeader('Content-Type') + '|' + Received));
end;

{ TRestClientIntoBodyTests }

procedure TRestClientIntoBodyTests.Setup;
var
  Builder: IWebHostBuilder;
begin
  Builder := TWebHost.CreateDefaultBuilder.UseUrls('http://127.0.0.1:0');
  Builder.Configure(
    procedure(App: IApplicationBuilder)
    begin
      App.MapEndpoint('POST', '/eco', Echo);
      App.MapEndpoint('PUT', '/eco', Echo);
      App.MapEndpoint('PATCH', '/eco', Echo);
      App.MapEndpoint('QUERY', '/eco', Echo);
    end);
  FHost := Builder.Build;
  FHost.Start;
  FBaseUrl := 'http://localhost:' + FHost.Port.ToString;
  TWatchedStream.Freed := False;
end;

procedure TRestClientIntoBodyTests.TearDown;
begin
  FHost.Stop;
  FHost := nil;
end;

procedure TRestClientIntoBodyTests.PostInto_SendsTheBody;
var
  Target: TMemoryStream;
  Resp: IRestResponse;
begin
  Target := TMemoryStream.Create;
  try
    Resp := RestClient(FBaseUrl).PostInto('/eco', Target, Body('{"a":1}'), True).Await;
    Should(Resp.StatusCode).Be(200);
    Should(TextOf(Target).StartsWith('POST|')).BeTrue;
    Should(TextOf(Target).EndsWith('|{"a":1}')).BeTrue;
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.PutInto_SendsTheBody;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    RestClient(FBaseUrl).PutInto('/eco', Target, Body('put-body'), True).Await;
    Should(TextOf(Target).StartsWith('PUT|')).BeTrue;
    Should(TextOf(Target).EndsWith('|put-body')).BeTrue;
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.PatchInto_SendsTheBody;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    RestClient(FBaseUrl).PatchInto('/eco', Target, Body('patch-body'), True).Await;
    Should(TextOf(Target).StartsWith('PATCH|')).BeTrue;
    Should(TextOf(Target).EndsWith('|patch-body')).BeTrue;
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.QueryInto_SendsTheBody_WithTheClientContentType;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    // Accented letters: the body goes as UTF-8 and comes back whole.
    RestClient(FBaseUrl).ContentTypeJson
      .QueryInto('/eco', Target, Body('{"filter":"' + #$E0#$E8#$EC + '"}'), True).Await;
    Should(TextOf(Target)).Be('QUERY|application/json|{"filter":"' + #$E0#$E8#$EC + '"}');
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.WithoutABody_WorksAsBefore;
var
  Target: TMemoryStream;
  Resp: IRestResponse;
begin
  Target := TMemoryStream.Create;
  try
    Resp := RestClient(FBaseUrl).PostInto('/eco', Target).Await;
    Should(Resp.StatusCode).Be(200);
    Should(TextOf(Target).StartsWith('POST|')).BeTrue;
    Should(TextOf(Target).EndsWith('|')).BeTrue;
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.ExecuteIntoAsync_IsOnTheFacade;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    RestClient(FBaseUrl).ExecuteIntoAsync(hmQUERY, '/eco', Target, Body('x'), True).Await;
    Should(TextOf(Target).StartsWith('QUERY|')).BeTrue;
    Should(TextOf(Target).EndsWith('|x')).BeTrue;
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.OwnsBody_TheClientFreesIt;
var
  Target: TMemoryStream;
begin
  Target := TMemoryStream.Create;
  try
    RestClient(FBaseUrl).PostInto('/eco', Target,
      TWatchedStream.Create('owned', TEncoding.UTF8), True).Await;
    Should(TWatchedStream.Freed).BeTrue;
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.NotOwned_TheCallerKeepsIt;
var
  Target: TMemoryStream;
  Mine: TWatchedStream;
begin
  Target := TMemoryStream.Create;
  Mine := TWatchedStream.Create('mine', TEncoding.UTF8);
  try
    RestClient(FBaseUrl).PostInto('/eco', Target, Mine).Await;
    Should(TWatchedStream.Freed).BeFalse;
    Should(TextOf(Target).EndsWith('|mine')).BeTrue;
  finally
    Mine.Free;
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.ErrorStatus_LeavesTheTargetUntouched;
var
  Target: TMemoryStream;
  Resp: IRestResponse;
begin
  Target := TMemoryStream.Create;
  try
    Resp := RestClient(FBaseUrl).PostInto('/missing', Target, Body('x'), True).Await;
    Should(Resp.StatusCode).Be(404);
    Should(Integer(Target.Size)).Be(0);
  finally
    Target.Free;
  end;
end;

procedure TRestClientIntoBodyTests.SameStreamForBodyAndTarget_IsRefused;
var
  Both: TWatchedStream;
  Raised: Boolean;
begin
  Both := TWatchedStream.Create('x', TEncoding.UTF8);
  try
    Raised := False;
    try
      RestClient(FBaseUrl).PostInto('/eco', Both, Both, True);
    except
      on EArgumentException do
        Raised := True;
    end;
    Should(Raised).BeTrue;
    // Also the caller's target: never freed, even with AOwnsBody.
    Should(TWatchedStream.Freed).BeFalse;
  finally
    Both.Free;
  end;
end;

procedure TRestClientIntoBodyTests.NilTarget_FreesAnOwnedBody;
var
  Raised: Boolean;
begin
  Raised := False;
  try
    RestClient(FBaseUrl).QueryInto('/eco', nil,
      TWatchedStream.Create('lost', TEncoding.UTF8), True);
  except
    on EArgumentNilException do
      Raised := True;
  end;
  Should(Raised).BeTrue;
  Should(TWatchedStream.Freed).BeTrue;
end;

procedure TRestClientIntoBodyTests.ExecuteIntoAsync_NilTarget_FreesAnOwnedBody;
var
  Raised: Boolean;
begin
  // The facade ExecuteIntoAsync shares the checks of the *Into verbs: an
  // owned body is not leaked when the call is refused.
  Raised := False;
  try
    RestClient(FBaseUrl).ExecuteIntoAsync(hmPOST, '/eco', nil,
      TWatchedStream.Create('lost', TEncoding.UTF8), True);
  except
    on EArgumentNilException do
      Raised := True;
  end;
  Should(Raised).BeTrue;
  Should(TWatchedStream.Freed).BeTrue;
end;

procedure TRestClientIntoBodyTests.NilTargetAndNilBody_IsTheNilTargetError;
var
  Raised: Boolean;
begin
  // nil = nil, but the error is the missing target, not "same stream".
  Raised := False;
  try
    RestClient(FBaseUrl).ExecuteIntoAsync(hmPOST, '/eco', nil, nil);
  except
    on EArgumentNilException do
      Raised := True;
  end;
  Should(Raised).BeTrue;
end;

end.

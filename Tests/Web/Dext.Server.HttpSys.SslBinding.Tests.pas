unit Dext.Server.HttpSys.SslBinding.Tests;

interface

uses
  System.Classes,
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Server.Engine.Interfaces,
  Dext.Server.Engine.Types,
  Dext.Server.HttpSys;

type
  /// <summary>
  ///   Startup validation of the http.sys SSL binding. These tests need no
  ///   binding on the machine: they use a port that has none, and check what
  ///   the engine says about it.
  /// </summary>
  [TestFixture('HTTP.sys - SSL binding validation at startup')]
  THttpSysSslBindingTests = class
  public
    [Test('Should validate the SSL binding by default')]
    procedure TestValidationIsOnByDefault;

    [Test('Should name 0.0.0.0, not +, in the netsh hint for a wildcard bind address')]
    procedure TestWildcardHintUsesZeroAddress;

    [Test('Should look a host name bind address up as a hostname (SNI) binding')]
    procedure TestHostNameIsLookedUpAsSniBinding;

    [Test('Should still reject an IPv6 bind address')]
    procedure TestIPv6AddressIsRejected;

    [Test('Should start without any SSL binding when ValidateSslBinding is False')]
    procedure TestValidationCanBeSkipped;
  end;

implementation

const
  // A port with no SSL binding of any kind on a normal machine.
  NO_BINDING_PORT = 47913;

/// <summary>Starts an HTTPS engine and returns the startup error ('' if none).</summary>
function StartError(const AOptions: TServerEngineOptions; const AAddress: string;
  out AClass: string): string;
var
  Engine: IDextServerEngine;
  Started: Boolean;
begin
  Result := '';
  AClass := '';
  Started := False;
  Engine := TDextHttpSysEngine.Create(AOptions);
  try
    Engine.Bind(AAddress, NO_BINDING_PORT);
    try
      Engine.Start;
      Started := True;
    except
      on E: Exception do
      begin
        AClass := E.ClassName;
        Result := E.Message;
      end;
    end;
  finally
    if Started then
      Engine.Stop(1000);
    Engine := nil;
  end;
end;

{ THttpSysSslBindingTests }

procedure THttpSysSslBindingTests.TestValidationIsOnByDefault;
begin
  Should(TServerEngineOptions.Default.ValidateSslBinding).BeTrue;
end;

procedure THttpSysSslBindingTests.TestWildcardHintUsesZeroAddress;
var
  Msg: string;
  ErrorClass: string;
begin
  Msg := StartError(TServerEngineOptions.Default.WithHttps, '+', ErrorClass);

  Should(ErrorClass).Be('EInvalidOperation');
  Should(Msg).Contain('ipport=0.0.0.0:' + NO_BINDING_PORT.ToString)
    .Because('netsh rejects ipport=+:<port>');
  Should(Msg).NotContain('+:')
    .Because('the query itself uses 0.0.0.0');
  Should(Msg).Contain('ValidateSslBinding');
end;

procedure THttpSysSslBindingTests.TestHostNameIsLookedUpAsSniBinding;
var
  Msg: string;
  ErrorClass: string;
begin
  Msg := StartError(TServerEngineOptions.Default.WithHttps,
    'dext-sni-test.invalid', ErrorClass);

  // Not "requires an IPv4 address" (the old answer), and not "Unable to
  // query ... (error 87)", which a wrong SNI query layout would produce.
  Should(ErrorClass).Be('EInvalidOperation');
  Should(Msg).Contain('hostnameport=dext-sni-test.invalid:' + NO_BINDING_PORT.ToString);
end;

procedure THttpSysSslBindingTests.TestIPv6AddressIsRejected;
var
  Msg: string;
  ErrorClass: string;
begin
  Msg := StartError(TServerEngineOptions.Default.WithHttps, '::1', ErrorClass);

  Should(ErrorClass).Be('EArgumentException');
  Should(Msg).Contain('requires an IPv4 address or a host name');
end;

procedure THttpSysSslBindingTests.TestValidationCanBeSkipped;
var
  Msg: string;
  ErrorClass: string;
begin
  Msg := StartError(TServerEngineOptions.Default.WithHttps
    .WithSslBindingValidation(False), '127.0.0.1', ErrorClass);

  Should(Msg).BeEmpty
    .Because('with the validation off the engine registers the prefix and starts');
end;

end.

unit Dext.Web.HandlerExceptions.Tests;

interface

uses
  System.SysUtils,
  Dext.Testing.Attributes,
  Dext.Web.Interfaces,
  Dext.Web.Routing.Attributes,
  Dext.Filters,
  Dext.Filters.BuiltIn;

type
  TExcBody = record
    Id: Integer;
  end;

  TExcDto = class
  private
    FId: Integer;
  public
    property Id: Integer read FId write FId;
  end;

  /// <summary>Handles a failed action by answering 418 through a result.</summary>
  AnswerTeapotOnErrorAttribute = class(ActionFilterAttribute)
  public
    procedure OnActionExecuted(AContext: IActionExecutedContext); override;
  end;

  /// <summary>Records the class of the exception OnActionExecuted received.</summary>
  RecordExceptionAttribute = class(ActionFilterAttribute)
  public
    class var LastExceptionClass: string;
    procedure OnActionExecuted(AContext: IActionExecutedContext); override;
  end;

  [ApiController, Route('/handler-exceptions')]
  THandlerExceptionsController = class
  public
    [HttpGet, Route('/notfound'), RecordException]
    procedure NotFound(const Ctx: IHttpContext);
    [HttpGet, Route('/server')]
    procedure ServerError(const Ctx: IHttpContext);
    [HttpGet, Route('/notfound-result')]
    function NotFoundResult: IResult;
    [HttpGet, Route('/handled'), AnswerTeapotOnError]
    procedure Handled(const Ctx: IHttpContext);
    [HttpGet, Route('/cached'), ResponseCache(60, 'public')]
    procedure Cached(const Ctx: IHttpContext);
  end;

  /// <summary>
  ///   An exception raised inside a handler or a controller action keeps its
  ///   status: it reaches UseExceptionHandler (EHttpException -> its status,
  ///   anything else -> 500 with the detail hidden outside Development), or
  ///   the server when no exception handler is configured. Only a failure of
  ///   the binding itself is answered with the 400 "model binding" problem.
  /// </summary>
  [TestFixture('Handler and action exceptions keep their status')]
  THandlerExceptionsTests = class
  public
    // Minimal API
    [Test('Static handler: ENotFoundException -> 404 (unchanged)')]
    procedure TestStaticHandlerNotFound;
    [Test('Bound handler: ENotFoundException -> 404, not 400')]
    procedure TestBoundHandlerNotFound;
    [Test('Bound handler: a server failure -> 500 with the detail hidden, not 400')]
    procedure TestBoundHandlerServerError;
    [Test('Bound handler returning IResult: ENotFoundException -> 404')]
    procedure TestBoundResultHandlerNotFound;
    [Test('Bound handler: a binding failure is still the 400 model binding problem')]
    procedure TestBindingFailureStillBadRequest;
    [Test('Bound handler without UseExceptionHandler: the exception reaches the server')]
    procedure TestBoundHandlerPropagatesWithoutExceptionHandler;
    // Controllers
    [Test('Controller action: ENotFoundException -> 404, not 500')]
    procedure TestControllerNotFound;
    [Test('Controller action: a message with quotes -> valid problem JSON, detail hidden')]
    procedure TestControllerServerErrorIsValidJson;
    [Test('Controller action returning IResult: ENotFoundException -> 404')]
    procedure TestControllerResultNotFound;
    [Test('Controller action: OnActionExecuted receives the exception')]
    procedure TestControllerFilterSeesException;
    [Test('Controller action: a filter that handles the exception answers with its result')]
    procedure TestControllerFilterHandlesException;
    [Test('Controller action: a failed action gets no Cache-Control from ResponseCache')]
    procedure TestControllerFailedActionNotCached;
    [Test('Controller action without UseExceptionHandler: the exception reaches the server')]
    procedure TestControllerPropagatesWithoutExceptionHandler;
  end;

implementation

uses
  System.JSON,
  Dext.Assertions,
  Dext.DI.Interfaces,
  Dext.Web,
  Dext.Web.Middleware,
  Dext.Web.Results,
  Dext.Web.WebApplication,
  Dext.Testing.WebApplicationFactory;

const
  // A parser-like message: quotes broke the hand-made JSON of the old 500.
  ServerMessage = 'Expected "{" but found identifier (database refused)';

{ AnswerTeapotOnErrorAttribute }

procedure AnswerTeapotOnErrorAttribute.OnActionExecuted(AContext: IActionExecutedContext);
begin
  if Assigned(AContext.Exception) then
  begin
    AContext.Result := Results.StatusCode(418);
    AContext.ExceptionHandled := True;
  end;
end;

{ RecordExceptionAttribute }

procedure RecordExceptionAttribute.OnActionExecuted(AContext: IActionExecutedContext);
begin
  if Assigned(AContext.Exception) then
    LastExceptionClass := AContext.Exception.ClassName
  else
    LastExceptionClass := '';
end;

{ THandlerExceptionsController }

procedure THandlerExceptionsController.NotFound(const Ctx: IHttpContext);
begin
  raise ENotFoundException.Create('item 42 not found');
end;

procedure THandlerExceptionsController.ServerError(const Ctx: IHttpContext);
begin
  raise Exception.Create(ServerMessage);
end;

function THandlerExceptionsController.NotFoundResult: IResult;
begin
  raise ENotFoundException.Create('item 42 not found');
end;

procedure THandlerExceptionsController.Handled(const Ctx: IHttpContext);
begin
  raise Exception.Create(ServerMessage);
end;

procedure THandlerExceptionsController.Cached(const Ctx: IHttpContext);
begin
  raise Exception.Create(ServerMessage);
end;

{ Helpers }

function CreateFactory(AWithExceptionHandler: Boolean): TDextApplicationFactory<TObject>;
begin
  // Keep the controller in the executable: nothing else references it.
  THandlerExceptionsController.Create.Free;

  Result := TDextApplicationFactory<TObject>.Create
    .WithTestServices(
      procedure(Services: TDextServices)
      begin
        Services.AddControllers;
      end)
    .WithConfigure(
      procedure(App: TWebApplication)
      begin
        if AWithExceptionHandler then
          App.Builder.UseExceptionHandler(TExceptionHandlerOptions.Production);

        App.Builder.MapGet('/handler-exceptions/static',
          procedure(Ctx: IHttpContext)
          begin
            raise ENotFoundException.Create('item 42 not found');
          end);
        App.Builder.MapPost<TExcBody>('/handler-exceptions/bound/notfound',
          procedure(B: TExcBody)
          begin
            raise ENotFoundException.Create('item 42 not found');
          end);
        App.Builder.MapPost<TExcBody>('/handler-exceptions/bound/server',
          procedure(B: TExcBody)
          begin
            raise Exception.Create(ServerMessage);
          end);
        App.Builder.MapPost<TExcBody, IResult>('/handler-exceptions/bound/result',
          function(B: TExcBody): IResult
          begin
            raise ENotFoundException.Create('item 42 not found');
          end);
        App.Builder.MapPost<TExcDto>('/handler-exceptions/bound/dto',
          procedure(D: TExcDto)
          begin
            // Not reached: the empty body fails the binding.
          end);

        App.MapControllers;
      end);
end;

procedure ShouldBeProblem(const AResp: IDextTestHttpResponse; AStatus: Integer);
var
  Json: TJSONValue;
begin
  Should(AResp.StatusCode).Be(AStatus);
  Should(AResp.ContentType).Contain('application/problem+json');
  // The body must be valid JSON.
  Json := TJSONObject.ParseJSONValue(AResp.Body);
  try
    Should(Json <> nil).BeTrue;
  finally
    Json.Free;
  end;
end;

{ THandlerExceptionsTests }

procedure THandlerExceptionsTests.TestStaticHandlerNotFound;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory(True);
  try
    ShouldBeProblem(Factory.CreateClient.Get('/handler-exceptions/static'), 404);
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestBoundHandlerNotFound;
var
  Factory: TDextApplicationFactory<TObject>;
  Resp: IDextTestHttpResponse;
begin
  Factory := CreateFactory(True);
  try
    Resp := Factory.CreateClient.PostJson('/handler-exceptions/bound/notfound', '{"Id":1}');
    ShouldBeProblem(Resp, 404);
    Should(Resp.Body).Contain('Not Found');
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestBoundHandlerServerError;
var
  Factory: TDextApplicationFactory<TObject>;
  Resp: IDextTestHttpResponse;
begin
  Factory := CreateFactory(True);
  try
    Resp := Factory.CreateClient.PostJson('/handler-exceptions/bound/server', '{"Id":1}');
    ShouldBeProblem(Resp, 500);
    // Production: the internal message does not reach the client.
    Should(Resp.Body).NotContain('database refused');
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestBoundResultHandlerNotFound;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory(True);
  try
    ShouldBeProblem(Factory.CreateClient.PostJson('/handler-exceptions/bound/result', '{"Id":1}'), 404);
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestBindingFailureStillBadRequest;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory(True);
  try
    ShouldBeProblem(Factory.CreateClient.PostJson('/handler-exceptions/bound/dto', ''), 400);
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestBoundHandlerPropagatesWithoutExceptionHandler;
var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
  Request: TProc;
begin
  Factory := CreateFactory(False);
  try
    Client := Factory.CreateClient;
    // Through a TProc variable: passed inline, the anonymous method would
    // pick the IInterface overload of Should.
    Request :=
      procedure
      begin
        Client.PostJson('/handler-exceptions/bound/notfound', '{"Id":1}');
      end;
    Should(Request).Throw<ENotFoundException>;
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestControllerNotFound;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory(True);
  try
    ShouldBeProblem(Factory.CreateClient.Get('/handler-exceptions/notfound'), 404);
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestControllerServerErrorIsValidJson;
var
  Factory: TDextApplicationFactory<TObject>;
  Resp: IDextTestHttpResponse;
begin
  Factory := CreateFactory(True);
  try
    Resp := Factory.CreateClient.Get('/handler-exceptions/server');
    ShouldBeProblem(Resp, 500);
    Should(Resp.Body).NotContain('database refused');
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestControllerResultNotFound;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory(True);
  try
    ShouldBeProblem(Factory.CreateClient.Get('/handler-exceptions/notfound-result'), 404);
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestControllerFilterSeesException;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  RecordExceptionAttribute.LastExceptionClass := '';
  Factory := CreateFactory(True);
  try
    Factory.CreateClient.Get('/handler-exceptions/notfound');
    Should(RecordExceptionAttribute.LastExceptionClass).Be(ENotFoundException.ClassName);
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestControllerFilterHandlesException;
var
  Factory: TDextApplicationFactory<TObject>;
begin
  Factory := CreateFactory(True);
  try
    Should(Factory.CreateClient.Get('/handler-exceptions/handled').StatusCode).Be(418);
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestControllerFailedActionNotCached;
var
  Factory: TDextApplicationFactory<TObject>;
  Resp: IDextTestHttpResponse;
begin
  Factory := CreateFactory(True);
  try
    Resp := Factory.CreateClient.Get('/handler-exceptions/cached');
    Should(Resp.StatusCode).Be(500);
    Should(Resp.GetHeader('Cache-Control')).BeEmpty;
  finally
    Factory.Free;
  end;
end;

procedure THandlerExceptionsTests.TestControllerPropagatesWithoutExceptionHandler;
var
  Factory: TDextApplicationFactory<TObject>;
  Client: IDextTestHttpClient;
  Request: TProc;
begin
  Factory := CreateFactory(False);
  try
    Client := Factory.CreateClient;
    // Through a TProc variable: passed inline, the anonymous method would
    // pick the IInterface overload of Should.
    Request :=
      procedure
      begin
        Client.Get('/handler-exceptions/notfound');
      end;
    Should(Request).Throw<ENotFoundException>;
  finally
    Factory.Free;
  end;
end;

end.

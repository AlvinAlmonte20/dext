unit Dext.Entity.LikeLiteral.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  Dext.Collections,
  Dext.Testing,
  Dext.Testing.Attributes,
  Dext.Entity,
  Dext.Entity.Attributes,
  Dext.Entity.Dialects,
  Dext.Entity.Context,
  Dext.Entity.Core,
  Dext.Specifications.Interfaces,
  FireDAC.Comp.Client,
  FireDAC.Phys.SQLite,
  FireDAC.Stan.Def,
  FireDAC.Stan.Async,
  FireDAC.Phys.SQLiteWrapper.Stat,
  Dext.Entity.Drivers.FireDAC;

type
  {$M+}
  [Table('like_codes')]
  TLikeCode = class
  private
    FId: Integer;
    FCode: string;
  public
    [PK]
    property Id: Integer read FId write FId;
    property Code: string read FCode write FCode;
  end;
  {$M-}

  TLikeContext = class(TDbContext)
  public
    function Codes: IDbSet<TLikeCode>;
  end;

  /// <summary>
  ///   StartsWith / EndsWith / Contains match their value literally: a % or _
  ///   in it is not a wildcard. In SQL they are a LIKE with the value escaped
  ///   and an ESCAPE clause; Like(pattern) keeps its wildcards.
  /// </summary>
  [Fixture]
  [Category('ORM'), Category('Unit'), Category('LikeLiteral')]
  TLikeLiteralSqlTests = class
  public
    [Test]
    procedure Test_StartsWith_EscapesWildcards;
    [Test]
    procedure Test_EndsWith_And_Contains_Patterns;
    [Test]
    procedure Test_SqlServer_Also_Escapes_Bracket;
    [Test]
    procedure Test_Other_Dialects_Keep_Bracket;
    [Test]
    procedure Test_Like_Keeps_Its_Wildcards;
    [Test]
    procedure Test_Cached_Statement_Gets_The_Same_Parameter;
  end;

  [Fixture]
  [Category('ORM'), Category('Unit'), Category('LikeLiteral')]
  TLikeLiteralMemoryTests = class
  public
    [Test]
    procedure Test_LikeMatches_Wildcards;
    [Test]
    procedure Test_Evaluator_StartsWith_Is_Literal;
    [Test]
    procedure Test_Evaluator_Like_Matches_Underscore;
    [Test]
    procedure Test_SmartTypes_Runtime_Agrees_With_SQL;
  end;

  /// <summary>The same expressions run against SQLite.</summary>
  [Fixture]
  [Category('ORM'), Category('Integration'), Category('LikeLiteral')]
  TLikeLiteralDbTests = class
  private
    FConn: TFDConnection;
    FContext: TLikeContext;
    function CountCodes(const AExpression: IExpression): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure Test_StartsWith_Underscore_Is_Literal;
    [Test]
    procedure Test_Contains_Percent_Is_Literal;
    [Test]
    procedure Test_StartsWith_Percent_Is_Literal;
    [Test]
    procedure Test_EndsWith_EscapeChar_Is_Literal;
    [Test]
    procedure Test_Like_Keeps_Its_Wildcards;
  end;

implementation

uses
  Dext.Specifications.Types,
  Dext.Specifications.Base,
  Dext.Specifications.Evaluator,
  Dext.Specifications.SQL.Generator,
  Dext.Core.SmartTypes;

function CodeProp: TPropExpression;
begin
  Result := Dext.Specifications.Types.Prop('Code');
end;

function WhereOf(const ADialect: ISQLDialect; const AExpression: IExpression;
  out AParam: string): string;
var
  Gen: TSQLWhereGenerator;
begin
  Gen := TSQLWhereGenerator.Create(ADialect);
  try
    Result := Gen.Generate(AExpression);
    AParam := Gen.Params['p1'].AsString;
  finally
    Gen.Free;
  end;
end;

{ TLikeContext }

function TLikeContext.Codes: IDbSet<TLikeCode>;
begin
  Result := Entities<TLikeCode>;
end;

{ TLikeLiteralSqlTests }

procedure TLikeLiteralSqlTests.Test_StartsWith_EscapesWildcards;
var
  SQL, Param: string;
begin
  SQL := WhereOf(TSQLiteDialect.Create, CodeProp.StartsWith('A_1%!'), Param);
  Should(SQL).Contain('LIKE :p1 ESCAPE ''!''');
  Should(Param).Be('A!_1!%!!%');
end;

procedure TLikeLiteralSqlTests.Test_EndsWith_And_Contains_Patterns;
var
  Param: string;
begin
  WhereOf(TPostgreSQLDialect.Create, CodeProp.EndsWith('_x'), Param);
  Should(Param).Be('%!_x');
  WhereOf(TPostgreSQLDialect.Create, CodeProp.Contains('100%'), Param);
  Should(Param).Be('%100!%%');
end;

procedure TLikeLiteralSqlTests.Test_SqlServer_Also_Escapes_Bracket;
var
  Param: string;
begin
  WhereOf(TSQLServerDialect.Create, CodeProp.Contains('[a]'), Param);
  Should(Param).Be('%![a]%');
end;

procedure TLikeLiteralSqlTests.Test_Other_Dialects_Keep_Bracket;
var
  Param: string;
begin
  // Elsewhere [ is not special, and escaping it is an error on Firebird and Oracle.
  WhereOf(TFirebirdDialect.Create, CodeProp.Contains('[a]'), Param);
  Should(Param).Be('%[a]%');
end;

procedure TLikeLiteralSqlTests.Test_Like_Keeps_Its_Wildcards;
var
  SQL, Param: string;
begin
  SQL := WhereOf(TSQLiteDialect.Create, CodeProp.Like('A_%'), Param);
  Should(SQL).NotContain('ESCAPE');
  Should(Param).Be('A_%');
end;

procedure TLikeLiteralSqlTests.Test_Cached_Statement_Gets_The_Same_Parameter;
var
  Gen: TSqlGenerator<TLikeCode>;
  Spec: ISpecification<TLikeCode>;
  First, Second: string;
begin
  // The second generation of the same specification comes from the SQL cache,
  // and its parameters from TSQLParamCollector: they must be escaped too.
  Spec := TSpecification<TLikeCode>.Create(CodeProp.StartsWith('Z_9'));
  Gen := TSqlGenerator<TLikeCode>.Create(TSQLiteDialect.Create, nil);
  try
    Gen.GenerateSelect(Spec);
    First := Gen.Params['p1'].AsString;
    Gen.GenerateSelect(Spec);
    Second := Gen.Params['p1'].AsString;
  finally
    Gen.Free;
  end;
  Should(First).Be('Z!_9%');
  Should(Second).Be(First);
end;

{ TLikeLiteralMemoryTests }

procedure TLikeLiteralMemoryTests.Test_LikeMatches_Wildcards;
begin
  Should(LikeMatches('ABC', 'A%', False)).BeTrue;
  Should(LikeMatches('ABC', 'A_C', False)).BeTrue;
  Should(LikeMatches('AC', 'A_C', False)).BeFalse;
  Should(LikeMatches('ABC', '%B%', False)).BeTrue;
  Should(LikeMatches('AXBXC', 'A%B%C', False)).BeTrue;
  Should(LikeMatches('MaCe', 'Ce%', False)).BeFalse;
  Should(LikeMatches('Cesar', '%es', False)).BeFalse;
  Should(LikeMatches('abc', 'ABC', True)).BeTrue;
  Should(LikeMatches('abc', 'ABC', False)).BeFalse;
  Should(LikeMatches('', '%', False)).BeTrue;
  Should(LikeMatches('', '_', False)).BeFalse;
end;

procedure TLikeLiteralMemoryTests.Test_Evaluator_StartsWith_Is_Literal;
var
  Code: TLikeCode;
begin
  Code := TLikeCode.Create;
  try
    Code.Code := 'AB1x';
    Should(TExpressionEvaluator.Evaluate(CodeProp.StartsWith('A_1'), Code)).BeFalse;
    Code.Code := 'A_1x';
    Should(TExpressionEvaluator.Evaluate(CodeProp.StartsWith('A_1'), Code)).BeTrue;
    Code.Code := 'MaCe';
    Should(TExpressionEvaluator.Evaluate(CodeProp.StartsWith('Ce'), Code)).BeFalse;
    Should(TExpressionEvaluator.Evaluate(CodeProp.EndsWith('ce'), Code)).BeTrue;
    Should(TExpressionEvaluator.Evaluate(CodeProp.Contains('ac'), Code)).BeTrue;
  finally
    Code.Free;
  end;
end;

procedure TLikeLiteralMemoryTests.Test_Evaluator_Like_Matches_Underscore;
var
  Code: TLikeCode;
begin
  Code := TLikeCode.Create;
  try
    Code.Code := 'AB1x';
    Should(TExpressionEvaluator.Evaluate(CodeProp.Like('A_1%'), Code)).BeTrue;
    Should(TExpressionEvaluator.Evaluate(CodeProp.Like('A%x'), Code)).BeTrue;
    Should(TExpressionEvaluator.Evaluate(CodeProp.Like('A_x'), Code)).BeFalse;
  finally
    Code.Free;
  end;
end;

procedure TLikeLiteralMemoryTests.Test_SmartTypes_Runtime_Agrees_With_SQL;
var
  S: Prop<string>;
begin
  S := 'MaCe';
  Should(Boolean(S.StartsWith('Ce'))).BeFalse;
  Should(Boolean(S.EndsWith('Ce'))).BeTrue;
  S := 'A_1x';
  Should(Boolean(S.StartsWith('A_1'))).BeTrue;
  S := 'AB1x';
  Should(Boolean(S.StartsWith('A_1'))).BeFalse;
  Should(Boolean(S.Like('A_1%'))).BeTrue;
  Should(Boolean(S.Like('A__'))).BeFalse;
end;

{ TLikeLiteralDbTests }

procedure TLikeLiteralDbTests.Setup;
const
  Codes: array[1..7] of string = ('A_1x', 'AB1x', '100%', '1000', '%x', 'x1', 'x!');
var
  I: Integer;
begin
  FConn := TFDConnection.Create(nil);
  FConn.DriverName := 'SQLite';
  FConn.Params.Add('Database=:memory:');
  FConn.Connected := True;
  FConn.ExecSQL('CREATE TABLE like_codes (Id INTEGER PRIMARY KEY, Code TEXT)');
  for I := Low(Codes) to High(Codes) do
    FConn.ExecSQL('INSERT INTO like_codes (Id, Code) VALUES (' + IntToStr(I) + ', ' +
      QuotedStr(Codes[I]) + ')');
  FContext := TLikeContext.Create(TFireDACConnection.Create(FConn, False), TSQLiteDialect.Create);
end;

procedure TLikeLiteralDbTests.TearDown;
begin
  FreeAndNil(FContext);
  FreeAndNil(FConn);
end;

function TLikeLiteralDbTests.CountCodes(const AExpression: IExpression): Integer;
begin
  Result := FContext.Codes.ToList(AExpression).Count;
  FContext.Clear;
end;

procedure TLikeLiteralDbTests.Test_StartsWith_Underscore_Is_Literal;
begin
  // Before: 2 (A_1x and AB1x)
  Should(CountCodes(CodeProp.StartsWith('A_1'))).Be(1);
end;

procedure TLikeLiteralDbTests.Test_Contains_Percent_Is_Literal;
begin
  // Before: 2 (100% and 1000)
  Should(CountCodes(CodeProp.Contains('100%'))).Be(1);
end;

procedure TLikeLiteralDbTests.Test_StartsWith_Percent_Is_Literal;
begin
  // Before: every row
  Should(CountCodes(CodeProp.StartsWith('%'))).Be(1);
end;

procedure TLikeLiteralDbTests.Test_EndsWith_EscapeChar_Is_Literal;
begin
  // The escape character itself is escaped
  Should(CountCodes(CodeProp.EndsWith('!'))).Be(1);
end;

procedure TLikeLiteralDbTests.Test_Like_Keeps_Its_Wildcards;
begin
  Should(CountCodes(CodeProp.Like('A_1%'))).Be(2);
end;

end.

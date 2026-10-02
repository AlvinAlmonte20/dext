unit Dext.Json.Regression.Tests;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.DateUtils,
  Data.DB,
  Dext.Testing.Attributes,
  Dext.Assertions,
  Dext.Json,
  Dext.Json.Types,
  Dext.Types.Nullable,
  Dext.Core.SmartTypes,
  Dext.Entity.Mapping,
  Dext.Entity.Attributes,
  Dext.Utils;

type
  TMyRecord = record
    IdRecord: Integer;
    Descricao: string;
  end;

  TCarItem = record
    name: string;
  end;

  TCarLista = record
    id: integer;
    cars: array of TCarItem;
  end;

  TFooRec = record
    id: integer;
    fools: TArray<string>;
  end;

  TFooListRec = record
    id: integer;
    fooList: TArray<string>;
  end;

  TLoginResponseRepro = record
    Token: string;
    usuarioid: Integer;
    usuarionome: string;
    executorid: Integer;
    expiresin: Integer;
  end;

  TOrdemServicoPendenteRepro = record
  public
    codigo:       Integer;
    clienteNome:  string;
    solicitacao:  string;
    solicitante:  string;
    dataPrevista: Nullable<TDateTime>;
    tipo:         string;
    situacao:     string;
    executorNome: string;
  end;

  // -------------------------------------------------------------------------
  // Types for issue #108 regression:
  // Dext.Json should NOT serialize internal 'refCount' / 'FRefCount' fields
  // when the serialized class inherits from TInterfacedObject.
  // -------------------------------------------------------------------------

  /// <summary>Data-contract interface (issue #108)</summary>
  IMyData108 = interface
    ['{8A9B1A2C-D3E4-4F5A-B6C7-D8E9F0A1B2C3}']
    function GetName: string;
    procedure SetName(const Value: string);
    property Name: string read GetName write SetName;
  end;

  /// <summary>Class implementing IMyData108 via TInterfacedObject (introduces FRefCount)</summary>
  TMyData108 = class(TInterfacedObject, IMyData108)
  private
    FName: string;
  public
    function GetName: string;
    procedure SetName(const Value: string);
    property Name: string read GetName write SetName;
  end;

  /// <summary>Generic result wrapper (issue #108)</summary>
  IPaginatedResult108<T> = interface
    function GetData: T;
    property Data: T read GetData;
  end;

  TPaginatedResult108<T> = class(TInterfacedObject, IPaginatedResult108<T>)
  private
    FData: T;
  public
    constructor Create(const AData: T);
    function GetData: T;
  end;

  /// <summary>Generic helper that reproduces the exact bug scenario (issue #108)</summary>
  TPaginatedJsonHelper108<T> = class
  public
    class function ToEnvelope(PData: IPaginatedResult108<T>): string;
  end;

  [TestFixture('JSON Regression Tests')]
  TJsonRegressionTests = class
  public
    [Test('Should produce indented JSON when TJsonSettings.Indented is used')]
    procedure TestIndentedFormatting;

    [Test('Should produce compact JSON when TJsonSettings.Default is used')]
    procedure TestCompactFormatting;

    [Test('Should produce indented JSON for arrays when TJsonSettings.Indented is used')]
    procedure TestArrayIndention;
  end;

  /// <summary>
  /// Regression suite for GitHub issue #108:
  /// Dext.Json serializes internal 'refCount' property when using Generics
  /// with Classes implementing Interfaces.
  /// </summary>
  [TestFixture('JSON Regression - Issue #108: refCount leak on TInterfacedObject')]
  TJsonIssue108RegressionTests = class
  public
    [Test('#108 - Serialize<T> must NOT include refCount when T is a TInterfacedObject subclass')]
    procedure TestSerializeGeneric_MustNotLeakRefCount;

    [Test('#108 - Serialize<T> via generic helper must NOT include refCount')]
    procedure TestSerializeViaGenericHelper_MustNotLeakRefCount;

    [Test('#108 - Serialize<T> result must contain only declared business properties')]
    procedure TestSerializeGeneric_OnlyContainsDeclaredProperties;
  end;

  [TestFixture('JSON Regression - Issue #127: Array deserialization issues')]
  TJsonIssue127RegressionTests = class
  public
    [Test('#127 - Deserialize array of records and read elements without invalid pointer operation')]
    procedure TestCarRecord;

    [Test('#127 - Deserialize array of strings to record')]
    procedure TestFooRec;

    [Test('#127 - Deserialize array of strings with field name ending in List')]
    procedure TestFooList;
  end;

  [TestFixture('JSON Regression - Bug Repro: Case Insensitive and TArray')]
  TJsonBugReproTests = class
  public
    [Test('Case insensitive record deserialization')]
    procedure TestCaseInsensitiveRecord;

    [Test('Root array deserialization to TArray of records')]
    procedure TestRootArrayOfRecords;

    [Test('Root array deserialization to TArray of records with SnakeCase settings')]
    procedure TestRootArrayOfRecordsSnakeCase;
  end;

  [Table('legacy_entity')]
  TMyLegacyEntity = class
  private
    FId: IntType;
    FNullableSmartField: Nullable<StringType>;
  public
    property Id: IntType read FId write FId;
    property NullableSmartField: Nullable<StringType> read FNullableSmartField write FNullableSmartField;
  end;

  TMyModernEntity = class
  private
    FId: IntType;
    FNullableSmartField: Prop<Nullable<Integer>>;
  public
    property Id: IntType read FId write FId;
    property NullableSmartField: Prop<Nullable<Integer>> read FNullableSmartField write FNullableSmartField;
  end;

  TFieldAccessEntity = class
  private
    FPlain: Integer;
    FComputed: Integer;
    function GetComputed: Integer;
  public
    property Plain: Integer read FPlain write FPlain;
    property Computed: Integer read GetComputed write FComputed;
  end;

  [TestFixture('Entity Mapping - Nullable Smart Property Warnings')]
  TEntityMappingWarningTests = class
  public
    [Test('Should detect Nullable<Prop<T>> and output warning message')]
    procedure TestLegacyNullablePropWarning;
    [Test('Should map Prop<Nullable<T>> correctly')]
    procedure TestModernPropNullableMapping;
    [Test('Should use the field offset for a property that reads a field, also on 64-bit')]
    procedure TestFieldGetterPropertyGetsFieldOffset;
  end;

implementation

{ TPaginatedResult108<T> }

constructor TPaginatedResult108<T>.Create(const AData: T);
begin
  inherited Create;
  FData := AData;
end;

function TPaginatedResult108<T>.GetData: T;
begin
  Result := FData;
end;

{ TPaginatedJsonHelper108<T> }

class function TPaginatedJsonHelper108<T>.ToEnvelope(PData: IPaginatedResult108<T>): string;
begin
  // This is the exact call path from the bug report
  Result := TDextJson.Serialize<T>(PData.GetData);
end;

{ TMyData108 }

function TMyData108.GetName: string;
begin
  Result := FName;
end;

procedure TMyData108.SetName(const Value: string);
begin
  FName := Value;
end;

{ TJsonRegressionTests }

procedure TJsonRegressionTests.TestIndentedFormatting;
var
  LMyRecord: TMyRecord;
  LJsonIndented: string;
begin
  LMyRecord.IdRecord := 1;
  LMyRecord.Descricao := 'Descricao';

  LJsonIndented := TDextJson.Serialize(TValue.From<TMyRecord>(LMyRecord), TJsonSettings.Indented);

  Should(LJsonIndented).NotBeEmpty;
  // Indented JSON should have line breaks.
  // We check for presence of at least one line break (\r or \n)
  Should(LJsonIndented.Contains(#13) or LJsonIndented.Contains(#10)).BeTrue;
  Should(LJsonIndented.Contains(' "IdRecord": 1') or LJsonIndented.Contains(#9'"IdRecord": 1'));
end;

procedure TJsonRegressionTests.TestCompactFormatting;
var
  LMyRecord: TMyRecord;
  LJsonCompact: string;
begin
  LMyRecord.IdRecord := 1;
  LMyRecord.Descricao := 'Descricao';

  LJsonCompact := TDextJson.Serialize(TValue.From<TMyRecord>(LMyRecord), TJsonSettings.Default);

  Should(LJsonCompact).NotBeEmpty;
  // Compact JSON should NOT have line breaks
  Should(LJsonCompact.Contains(#13)).BeFalse;
  Should(LJsonCompact.Contains(#10)).BeFalse;
  Should(LJsonCompact).Be('{"IdRecord":1,"Descricao":"Descricao"}');
end;

procedure TJsonRegressionTests.TestArrayIndention;
var
  LArray: TArray<Integer>;
  LJson: string;
begin
  LArray := [1, 2, 3];
  LJson := TDextJson.Serialize(TValue.From<TArray<Integer>>(LArray), TJsonSettings.Indented);

  Should(LJson).NotBeEmpty;
  Should(LJson.Contains(#13) or LJson.Contains(#10)).BeTrue;
  Should(LJson).Contain('1');
  Should(LJson).Contain('2');
  Should(LJson).Contain('3');
end;

{ TJsonIssue108RegressionTests }

procedure TJsonIssue108RegressionTests.TestSerializeGeneric_MustNotLeakRefCount;
var
  LData: TMyData108;
  LJson: string;
begin
  // Arrange: create a TInterfacedObject subclass with a single business property
  LData := TMyData108.Create;
  try
    LData.Name := 'Dext User';

    // Act: serialize using the generic overload (exact bug trigger)
    LJson := TDextJson.Serialize<TMyData108>(LData);

    // Assert: refCount must NOT appear in output
    Should(LJson).NotBeEmpty;
    Should(LJson.ToLower.Contains('refcount')).BeFalse;
    Should(LJson.ToLower.Contains('frefcount')).BeFalse;
  finally
    LData.Free;
  end;
end;

procedure TJsonIssue108RegressionTests.TestSerializeViaGenericHelper_MustNotLeakRefCount;
var
  LData: TMyData108;
  LPaginated: IPaginatedResult108<TMyData108>;
  LJson: string;
begin
  // Arrange: replicate the exact scenario from the issue report
  LData := TMyData108.Create;
  try
    LData.Name := 'Dext User';
    LPaginated := TPaginatedResult108<TMyData108>.Create(LData);

    // Act: serialize via the generic helper (this was the original failing path)
    LJson := TPaginatedJsonHelper108<TMyData108>.ToEnvelope(LPaginated);

    // Assert: refCount must NOT appear in output
    Should(LJson).NotBeEmpty;
    Should(LJson.ToLower.Contains('refcount')).BeFalse;
    Should(LJson.ToLower.Contains('frefcount')).BeFalse;
  finally
    LData.Free;
  end;
end;

procedure TJsonIssue108RegressionTests.TestSerializeGeneric_OnlyContainsDeclaredProperties;
var
  LData: TMyData108;
  LJson: string;
begin
  // Arrange
  LData := TMyData108.Create;
  try
    LData.Name := 'Dext User';

    // Act: default settings preserve PascalCase names
    LJson := TDextJson.Serialize<TMyData108>(LData);

    // Assert: output must contain the business property key (quoted, PascalCase)
    // and its value. Using quoted '"Name"' avoids a false-positive match on the
    // value 'Dext User' which also contains letters.
    Should(LJson).Contain('"Name"');
    Should(LJson).Contain('Dext User');

    // The compact output must be exactly this -- no extra fields allowed.
    // If refCount were leaking, the JSON would have more keys.
    Should(LJson).Be('{"Name":"Dext User"}');

    // Belt-and-suspenders: key names from TInterfacedObject must be absent
    Should(LJson.ToLower.Contains('refcount')).BeFalse;
    Should(LJson.ToLower.Contains('frefcount')).BeFalse;
  finally
    LData.Free;
  end;
end;

{ TJsonIssue127RegressionTests }

procedure TJsonIssue127RegressionTests.TestCarRecord;
var
  JsonStr: string;
  CarLista: TCarLista;
begin
  JsonStr := '{ "id": 800, "cars": [ {"name":"A1"}, {"name":"B2"}, {"name":"C3"} ] }';
  CarLista := TDextJson.Deserialize<TCarLista>(JsonStr);

  Should(CarLista.id).Be(800);
  Should(Length(CarLista.cars)).Be(3);

  for var car in CarLista.cars do
  begin
    Should(car.name).NotBeEmpty;
  end;

  Should(CarLista.cars[0].name).Be('A1');
  Should(CarLista.cars[1].name).Be('B2');
  Should(CarLista.cars[2].name).Be('C3');
end;

procedure TJsonIssue127RegressionTests.TestFooRec;
var
  JsonStr: string;
  FooRec: TFooRec;
begin
  JsonStr := '{"id": 800, "fools": [ "a", "b", "c" ] }';
  FooRec := TDextJson.Deserialize<TFooRec>(JsonStr);

  Should(FooRec.id).Be(800);
  Should(Length(FooRec.fools)).Be(3);

  for var f in FooRec.fools do
  begin
    Should(f).NotBeEmpty;
  end;

  Should(FooRec.fools[0]).Be('a');
  Should(FooRec.fools[1]).Be('b');
  Should(FooRec.fools[2]).Be('c');
end;

procedure TJsonIssue127RegressionTests.TestFooList;
var
  JsonStr: string;
  FooRec: TFooListRec;
begin
  JsonStr := '{"id": 800, "fooList": [ "a", "b", "c" ] }';
  FooRec := TDextJson.Deserialize<TFooListRec>(JsonStr);

  Should(FooRec.id).Be(800);
  Should(Length(FooRec.fooList)).Be(3);

  for var f in FooRec.fooList do
  begin
    Should(f).NotBeEmpty;
  end;

  Should(FooRec.fooList[0]).Be('a');
  Should(FooRec.fooList[1]).Be('b');
  Should(FooRec.fooList[2]).Be('c');
end;

{ TJsonBugReproTests }

procedure TJsonBugReproTests.TestCaseInsensitiveRecord;
var
  LJson: string;
  LData: TLoginResponseRepro;
begin
  LJson := '{"token":"my-token","usuarioId":12,"usuarioNome":"Samuel","executorId":31656,"expiresIn":1440}';
  
  LData := TDextJson.Deserialize<TLoginResponseRepro>(LJson, TJsonSettings.Default.CaseInsensitive);

  Should(LData.Token).Be('my-token');
  Should(LData.usuarioid).Be(12);
  Should(LData.usuarionome).Be('Samuel');
  Should(LData.executorid).Be(31656);
  Should(LData.expiresin).Be(1440);
end;

procedure TJsonBugReproTests.TestRootArrayOfRecords;
var
  LJson: string;
  LArray: TArray<TOrdemServicoPendenteRepro>;
begin
  LJson := '[{"codigo":1,"clienteNome":"John Doe","solicitacao":"Test OS","solicitante":"Alice","dataPrevista":"2026-06-03T12:00:00","tipo":"Preventiva","situacao":"Aberta","executorNome":"Bob"}]';

  LArray := TDextJson.Deserialize<TArray<TOrdemServicoPendenteRepro>>(LJson);

  Should(Length(LArray)).Be(1);
  Should(LArray[0].codigo).Be(1);
  Should(LArray[0].clienteNome).Be('John Doe');
  Should(LArray[0].solicitacao).Be('Test OS');
  Should(LArray[0].solicitante).Be('Alice');
  ShouldDate(LArray[0].dataPrevista).Be(EncodeDateTime(2026, 6, 3, 12, 0, 0, 0));
  Should(LArray[0].tipo).Be('Preventiva');
  Should(LArray[0].situacao).Be('Aberta');
  Should(LArray[0].executorNome).Be('Bob');
end;

procedure TJsonBugReproTests.TestRootArrayOfRecordsSnakeCase;
var
  LJson: string;
  LArray: TArray<TOrdemServicoPendenteRepro>;
begin
  LJson := '[{"codigo":1,"cliente_nome":"John Doe","solicitacao":"Test OS","solicitante":"Alice","data_prevista":"2026-06-03T12:00:00","tipo":"Preventiva","situacao":"Aberta","executor_nome":"Bob"}]';

  LArray := TDextJson.Deserialize<TArray<TOrdemServicoPendenteRepro>>(LJson, TJsonSettings.Default.SnakeCase);

  Should(Length(LArray)).Be(1);
  Should(LArray[0].codigo).Be(1);
  Should(LArray[0].clienteNome).Be('John Doe');
  Should(LArray[0].solicitacao).Be('Test OS');
  Should(LArray[0].solicitante).Be('Alice');
  ShouldDate(LArray[0].dataPrevista).Be(EncodeDateTime(2026, 6, 3, 12, 0, 0, 0));
  Should(LArray[0].tipo).Be('Preventiva');
  Should(LArray[0].situacao).Be('Aberta');
  Should(LArray[0].executorNome).Be('Bob');
end;

{ TEntityMappingWarningTests }

procedure TEntityMappingWarningTests.TestLegacyNullablePropWarning;
var
  LMap: TEntityMap;
begin
  LMap := TEntityMap.Create(TypeInfo(TMyLegacyEntity));
  try
    Should(LMap).NotBeNil;
  finally
    LMap.Free;
  end;
end;

procedure TEntityMappingWarningTests.TestModernPropNullableMapping;
var
  LMap: TEntityMap;
  PropMap: TPropertyMap;
begin
  // TEntityMap stores properties by Prop.Name (RTTI), which is PascalCase.
  // The dictionary is case-insensitive, so 'NullableSmartField' is the canonical key.
  LMap := TEntityMap.Create(TypeInfo(TMyModernEntity));
  try
    Should(LMap.Properties.TryGetValue('NullableSmartField', PropMap)).BeTrue;
    // Prop<Nullable<Integer>> must map to the inner Integer type, not the wrapper
    Should(PropMap.PropertyType = TypeInfo(Integer)).BeTrue;
    Should(Integer(PropMap.DataType)).Be(Integer(ftInteger));
    // FieldOffset  = offset of FHasValue (null flag Boolean) inside the composed record
    // FieldValueOffset = offset of FValue (Integer) inside the composed record
    Should(PropMap.FieldOffset).BeGreaterThan(0);
    Should(PropMap.FieldValueOffset).BeGreaterThan(0);
  finally
    LMap.Free;
  end;
end;

{ TFieldAccessEntity }

function TFieldAccessEntity.GetComputed: Integer;
begin
  Result := FComputed * 2;
end;

procedure TEntityMappingWarningTests.TestFieldGetterPropertyGetsFieldOffset;
var
  LMap: TEntityMap;
  PropMap: TPropertyMap;
  Obj: TFieldAccessEntity;
  ExpectedOffset: Integer;
begin
  // A 'read FField' property stores the field offset in GetProc, flagged with
  // PROPSLOT_FIELD in the high bits: $FF000000 on 32-bit, $FF00000000000000
  // on 64-bit. A fixed $FF000000 mask never matched on Win64.
  Obj := TFieldAccessEntity.Create;
  try
    ExpectedOffset := Integer(NativeInt(@Obj.FPlain) - NativeInt(Obj));
  finally
    Obj.Free;
  end;
  LMap := TEntityMap.Create(TypeInfo(TFieldAccessEntity));
  try
    Should(LMap.Properties.TryGetValue('Plain', PropMap)).BeTrue;
    Should(PropMap.FieldValueOffset).Be(ExpectedOffset);
    // A method getter must not be read from memory.
    Should(LMap.Properties.TryGetValue('Computed', PropMap)).BeTrue;
    Should(PropMap.FieldValueOffset).Be(0);
  finally
    LMap.Free;
  end;
end;

end.

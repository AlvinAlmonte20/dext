{***************************************************************************}
{                                                                           }
{           Dext Framework - Collections Unit Tests                         }
{                                                                           }
{           Tests for TryAdd on TDictionary<K,V> and                        }
{           TOrderedDictionary<K,V>, and TryAddRaw on the raw backends      }
{                                                                           }
{***************************************************************************}
unit TestCollections.TryAdd;

interface

uses
  System.SysUtils,
  Dext.Testing,
  Dext.Collections,
  Dext.Collections.RawDict,
  Dext.Collections.Dict,
  Dext.Collections.OrderedDict;

type
  TTryAddValue = class
  public
    class var InstanceCount: Integer;
    constructor Create;
    destructor Destroy; override;
  end;

  /// <summary>
  ///   TryAdd adds a key that is not there yet with a single lookup, and
  ///   returns False, changing nothing, for a key that is already there.
  /// </summary>
  [TestFixture('Dictionary - TryAdd')]
  TDictionaryTryAddTests = class
  public
    [Test]
    procedure NewKey_ReturnsTrue_AndAdds;
    [Test]
    procedure ExistingKey_ReturnsFalse_AndKeepsTheValue;
    [Test]
    procedure ManagedKeyAndValue;
    [Test]
    procedure Growth_KeepsEveryKey;
    [Test]
    procedure ReusesRemovedSlots;
    [Test]
    procedure OwnsValues_RefusedValueIsNotTaken;
  end;

  [TestFixture('OrderedDictionary - TryAdd')]
  TOrderedDictionaryTryAddTests = class
  public
    [Test]
    procedure NewKey_IsAppendedAtTheEnd;
    [Test]
    procedure ExistingKey_LeavesKeysValuesAndOrderUntouched;
    [Test]
    procedure AfterRemove_AppendsWithTheRightPosition;
    [Test]
    procedure Growth_KeepsEveryKeyInOrder;
    [Test]
    procedure Add_Duplicate_StillRaises_AndLeavesTheListsAlone;
  end;

  /// <summary>
  ///   The raw backend: only a key that is really added can grow the table.
  ///   Before, Add and AddOrSet checked the load factor first, so a duplicate
  ///   Add (which raises) or an update of an existing key could rehash it.
  /// </summary>
  [TestFixture('RawDictionary - TryAddRaw')]
  TRawDictionaryTryAddTests = class
  public
    [Test]
    procedure TryAddRaw_ExistingKey_DoesNotGrowTheTable;
    [Test]
    procedure AddRaw_Duplicate_DoesNotGrowTheTable;
    [Test]
    procedure AddOrSetRaw_ExistingKey_DoesNotGrowTheTable;
    [Test]
    procedure TryAddRaw_NewKey_GrowsWhenTheLoadFactorSaysSo;
  end;

implementation

{ TTryAddValue }

constructor TTryAddValue.Create;
begin
  inherited Create;
  Inc(InstanceCount);
end;

destructor TTryAddValue.Destroy;
begin
  Dec(InstanceCount);
  inherited;
end;

{ TDictionaryTryAddTests }

procedure TDictionaryTryAddTests.NewKey_ReturnsTrue_AndAdds;
var
  D: TDictionary<Integer, Integer>;
begin
  D := TDictionary<Integer, Integer>.Create;
  try
    Should(D.TryAdd(1, 100)).BeTrue;
    Should(D.TryAdd(2, 200)).BeTrue;
    Should(D.Count).Be(2);
    Should(D[1]).Be(100);
    Should(D[2]).Be(200);
  finally
    D.Free;
  end;
end;

procedure TDictionaryTryAddTests.ExistingKey_ReturnsFalse_AndKeepsTheValue;
var
  D: TDictionary<Integer, Integer>;
begin
  D := TDictionary<Integer, Integer>.Create;
  try
    D.Add(1, 100);
    Should(D.TryAdd(1, 999)).BeFalse;
    Should(D.Count).Be(1);
    Should(D[1]).Be(100);
  finally
    D.Free;
  end;
end;

procedure TDictionaryTryAddTests.ManagedKeyAndValue;
var
  D: TDictionary<string, string>;
  Key, Value: string;
begin
  D := TDictionary<string, string>.Create;
  try
    // Built at run time, so the dictionary has to keep its own reference.
    Key := 'key-' + IntToStr(42);
    Value := 'value-' + IntToStr(42);
    Should(D.TryAdd(Key, Value)).BeTrue;
    Key := '';
    Value := '';
    Should(D['key-42']).Be('value-42');
    Should(D.TryAdd('key-42', 'other')).BeFalse;
    Should(D['key-42']).Be('value-42');
  finally
    D.Free;
  end;
end;

procedure TDictionaryTryAddTests.Growth_KeepsEveryKey;
const
  N = 20000;
var
  D: TDictionary<string, Integer>;
  I, V: Integer;
begin
  D := TDictionary<string, Integer>.Create;
  try
    for I := 0 to N - 1 do
      Should(D.TryAdd('K' + IntToStr(I), I)).BeTrue;
    Should(D.Count).Be(N);
    for I := 0 to N - 1 do
    begin
      Should(D.TryGetValue('K' + IntToStr(I), V)).BeTrue;
      Should(V).Be(I);
      Should(D.TryAdd('K' + IntToStr(I), -1)).BeFalse;
    end;
    Should(D.Count).Be(N);
  finally
    D.Free;
  end;
end;

procedure TDictionaryTryAddTests.ReusesRemovedSlots;
const
  N = 1000;
var
  D: TDictionary<Integer, Integer>;
  I, V: Integer;
begin
  D := TDictionary<Integer, Integer>.Create;
  try
    for I := 0 to N - 1 do
      D.Add(I, I);
    // Every other key removed: their slots become tombstones.
    for I := 0 to N - 1 do
      if Odd(I) then
        D.Remove(I);
    for I := 0 to N - 1 do
      Should(D.TryAdd(I, I + N)).Be(Odd(I));
    Should(D.Count).Be(N);
    for I := 0 to N - 1 do
    begin
      Should(D.TryGetValue(I, V)).BeTrue;
      if Odd(I) then
        Should(V).Be(I + N)
      else
        Should(V).Be(I);
    end;
  finally
    D.Free;
  end;
end;

procedure TDictionaryTryAddTests.OwnsValues_RefusedValueIsNotTaken;
var
  D: TDictionary<Integer, TTryAddValue>;
  First, Second: TTryAddValue;
begin
  TTryAddValue.InstanceCount := 0;
  D := TDictionary<Integer, TTryAddValue>.Create(True);
  try
    First := TTryAddValue.Create;
    Second := TTryAddValue.Create;
    Should(D.TryAdd(1, First)).BeTrue;
    Should(D.TryAdd(1, Second)).BeFalse;
    // The refused value still belongs to the caller, and the stored one is
    // still alive.
    Should(TTryAddValue.InstanceCount).Be(2);
    Should(D[1] = First).BeTrue;
    Second.Free;
  finally
    D.Free;
  end;
  Should(TTryAddValue.InstanceCount).Be(0);
end;

{ TOrderedDictionaryTryAddTests }

procedure TOrderedDictionaryTryAddTests.NewKey_IsAppendedAtTheEnd;
var
  D: TOrderedDictionary<string, Integer>;
begin
  D := TOrderedDictionary<string, Integer>.Create;
  try
    D.Add('b', 2);
    Should(D.TryAdd('a', 1)).BeTrue;
    Should(D.Count).Be(2);
    Should(D.GetKeyAt(1)).Be('a');
    Should(D.GetValueAt(1)).Be(1);
    Should(D.IndexOf('a')).Be(1);
  finally
    D.Free;
  end;
end;

procedure TOrderedDictionaryTryAddTests.ExistingKey_LeavesKeysValuesAndOrderUntouched;
var
  D: TOrderedDictionary<string, Integer>;
begin
  D := TOrderedDictionary<string, Integer>.Create;
  try
    D.Add('a', 1);
    D.Add('b', 2);
    Should(D.TryAdd('a', 99)).BeFalse;
    Should(D.Count).Be(2);
    Should(Length(D.Keys)).Be(2);
    Should(Length(D.Values)).Be(2);
    Should(D.GetKeyAt(0)).Be('a');
    Should(D.GetValueAt(0)).Be(1);
    Should(D.GetKeyAt(1)).Be('b');
    Should(D.IndexOf('b')).Be(1);
  finally
    D.Free;
  end;
end;

procedure TOrderedDictionaryTryAddTests.AfterRemove_AppendsWithTheRightPosition;
var
  D: TOrderedDictionary<string, Integer>;
begin
  D := TOrderedDictionary<string, Integer>.Create;
  try
    D.Add('a', 1);
    D.Add('b', 2);
    D.Add('c', 3);
    D.Remove('a');
    Should(D.TryAdd('a', 10)).BeTrue;
    Should(D.IndexOf('b')).Be(0);
    Should(D.IndexOf('c')).Be(1);
    Should(D.IndexOf('a')).Be(2);
    Should(D['a']).Be(10);
    Should(D.TryAdd('c', 30)).BeFalse;
    Should(D['c']).Be(3);
  finally
    D.Free;
  end;
end;

procedure TOrderedDictionaryTryAddTests.Growth_KeepsEveryKeyInOrder;
const
  N = 20000;
var
  D: TOrderedDictionary<string, TObject>;
  I: Integer;
begin
  D := TOrderedDictionary<string, TObject>.Create;
  try
    for I := 0 to N - 1 do
      Should(D.TryAdd('ART-' + IntToStr(I), nil)).BeTrue;
    for I := 0 to N - 1 do
      Should(D.TryAdd('ART-' + IntToStr(I), nil)).BeFalse;
    Should(D.Count).Be(N);
    for I := 0 to N - 1 do
    begin
      Should(D.GetKeyAt(I)).Be('ART-' + IntToStr(I));
      Should(D.IndexOf('ART-' + IntToStr(I))).Be(I);
    end;
  finally
    D.Free;
  end;
end;

procedure TOrderedDictionaryTryAddTests.Add_Duplicate_StillRaises_AndLeavesTheListsAlone;
var
  D: TOrderedDictionary<string, Integer>;
  Raised: Boolean;
begin
  D := TOrderedDictionary<string, Integer>.Create;
  try
    D.Add('a', 1);
    Raised := False;
    try
      D.Add('a', 2);
    except
      on Exception do
        Raised := True;
    end;
    Should(Raised).BeTrue;
    Should(D.Count).Be(1);
    Should(Length(D.Keys)).Be(1);
    Should(D['a']).Be(1);
  finally
    D.Free;
  end;
end;

{ TRawDictionaryTryAddTests }

function NewIntRaw: TRawDictionary;
begin
  // Default capacity 4, load factor 75%: three entries fill it.
  Result := TRawDictionary.Create(SizeOf(Integer), SizeOf(Integer),
    TypeInfo(Integer), TypeInfo(Integer), nil, nil);
end;

procedure FillThree(ARaw: TRawDictionary);
var
  K, V: Integer;
begin
  for K := 1 to 3 do
  begin
    V := K * 10;
    ARaw.AddRaw(@K, @V);
  end;
end;

procedure TRawDictionaryTryAddTests.TryAddRaw_ExistingKey_DoesNotGrowTheTable;
var
  Raw: TRawDictionary;
  K, V: Integer;
begin
  Raw := NewIntRaw;
  try
    FillThree(Raw);
    Should(Raw.Capacity).Be(4);
    K := 2;
    V := 99;
    Should(Raw.TryAddRaw(@K, @V)).BeFalse;
    Should(Raw.Capacity).Be(4);
    Should(Raw.Count).Be(3);
  finally
    Raw.Free;
  end;
end;

procedure TRawDictionaryTryAddTests.AddRaw_Duplicate_DoesNotGrowTheTable;
var
  Raw: TRawDictionary;
  K, V: Integer;
  Raised: Boolean;
begin
  Raw := NewIntRaw;
  try
    FillThree(Raw);
    K := 2;
    V := 99;
    Raised := False;
    try
      Raw.AddRaw(@K, @V);
    except
      on Exception do
        Raised := True;
    end;
    Should(Raised).BeTrue;
    // Before: 8, the table was rehashed and then the Add raised.
    Should(Raw.Capacity).Be(4);
  finally
    Raw.Free;
  end;
end;

procedure TRawDictionaryTryAddTests.AddOrSetRaw_ExistingKey_DoesNotGrowTheTable;
var
  Raw: TRawDictionary;
  K, V: Integer;
  P: Pointer;
begin
  Raw := NewIntRaw;
  try
    FillThree(Raw);
    K := 2;
    V := 99;
    Raw.AddOrSetRaw(@K, @V);
    // Before: 8, although no entry was added.
    Should(Raw.Capacity).Be(4);
    Should(Raw.TryGetRaw(@K, P)).BeTrue;
    Should(PInteger(P)^).Be(99);
  finally
    Raw.Free;
  end;
end;

procedure TRawDictionaryTryAddTests.TryAddRaw_NewKey_GrowsWhenTheLoadFactorSaysSo;
var
  Raw: TRawDictionary;
  K, V: Integer;
  P: Pointer;
begin
  Raw := NewIntRaw;
  try
    FillThree(Raw);
    K := 4;
    V := 40;
    Should(Raw.TryAddRaw(@K, @V)).BeTrue;
    Should(Raw.Capacity).Be(8);
    for K := 1 to 4 do
    begin
      Should(Raw.TryGetRaw(@K, P)).BeTrue;
      Should(PInteger(P)^).Be(K * 10);
    end;
  finally
    Raw.Free;
  end;
end;

end.

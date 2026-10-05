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
{                                                                           }
{  Author:  Cesar Romero                                                    }
{  Created: 2025-12-08                                                      }
{                                                                           }
{***************************************************************************}
unit Dext.Specifications.Evaluator;

interface

uses
  System.SysUtils,
  System.Rtti,
  System.TypInfo,
  System.Variants,
  Dext.Collections.Dict,
  Dext.Specifications.Interfaces,
  Dext.Specifications.Types;

type
  /// <summary>
  ///   Evaluates an expression tree against an object instance or dictionary in memory.
  /// </summary>
  TExpressionEvaluator = class
  public
    class function Evaluate(const AExpression: IExpression; const AObject: TObject): Boolean; overload;
    class function Evaluate(const AExpression: IExpression; const ADict: TDictionary<string, Variant>): Boolean; overload;
  end;

implementation
    
uses
  Dext.Core.Reflection;

type
  TEvaluatorVisitor = class(TInterfacedObject, IExpressionVisitor)
  private
    FObject: TObject;
    FDict: TDictionary<string, Variant>;
    FResult: Boolean;
    
    function GetPropertyValue(const APropertyName: string): TValue;
    function ResolveValue(const AExpression: IExpression): TValue;
    function Compare(const Left, Right: TValue; Op: TBinaryOperator): Boolean;
    function Calculate(const Left, Right: TValue; Op: TArithmeticOperator): TValue;
  public
    constructor Create(AObject: TObject); overload;
    constructor Create(ADict: TDictionary<string, Variant>); overload;
    procedure Visit(const AExpression: IExpression);
    property Result: Boolean read FResult;
  end;

{ TExpressionEvaluator }

class function TExpressionEvaluator.Evaluate(const AExpression: IExpression; const AObject: TObject): Boolean;
var
  Visitor: TEvaluatorVisitor;
begin
  if AExpression = nil then Exit(True);
  
  Visitor := TEvaluatorVisitor.Create(AObject);
  try
    Visitor.Visit(AExpression);
    Result := Visitor.Result;
  finally
    Visitor.Free;
  end;
end;

class function TExpressionEvaluator.Evaluate(const AExpression: IExpression; const ADict: TDictionary<string, Variant>): Boolean;
var
  Visitor: TEvaluatorVisitor;
begin
  if AExpression = nil then Exit(True);
  
   Visitor := TEvaluatorVisitor.Create(ADict);
  try
    Visitor.Visit(AExpression);
    Result := Visitor.Result;
  finally
    Visitor.Free;
  end;
end;

{ TEvaluatorVisitor }

constructor TEvaluatorVisitor.Create(AObject: TObject);
begin
  FObject := AObject;
  FDict := nil;
end;

constructor TEvaluatorVisitor.Create(ADict: TDictionary<string, Variant>);
begin
  FObject := nil;
  FDict := ADict;
end;

function TEvaluatorVisitor.GetPropertyValue(const APropertyName: string): TValue;
var
  Typ: TRttiType;
  Prop, P: TRttiProperty;
  Fld, F: TRttiField;
  Val: TValue;
  V: Variant;
begin
  Val := TValue.Empty;
  
  if FDict <> nil then
  begin
    if FDict.TryGetValue(APropertyName, V) then
      Val := TValue.FromVariant(V);
  end
  else if FObject <> nil then
  begin
    Typ := TReflection.Context.GetType(FObject.ClassType);
    Prop := Typ.GetProperty(APropertyName);
    
    if Prop = nil then
    begin
      // Fallback: Case-insensitive search for properties
      for P in Typ.GetProperties do
        if SameText(P.Name, APropertyName) then
        begin
          Prop := P;
          Break;
        end;
    end;

    if Prop <> nil then
      Val := Prop.GetValue(FObject)
    else
    begin
      Fld := Typ.GetField(APropertyName);
      if Fld = nil then
      begin
        // Fallback: Case-insensitive search for fields
        for F in Typ.GetFields do
          if SameText(F.Name, APropertyName) then
          begin
            Fld := F;
            Break;
          end;
      end;

      if Fld <> nil then
        Val := Fld.GetValue(FObject);
    end;
  end;
  
  if Val.IsEmpty then
    raise Exception.CreateFmt('Property or Field "%s" not found', [APropertyName]);

  // Unwrap Smart Types (Prop<T>)
  if (Val.Kind = tkRecord) and string(Val.TypeInfo.Name).StartsWith('Prop<') then
  begin
    Fld := TReflection.Context.GetType(Val.TypeInfo).GetField('FValue');
    if Fld <> nil then
      Val := Fld.GetValue(Val.GetReferenceToRawData);
  end;
  
  Result := Val;
end;

function TEvaluatorVisitor.ResolveValue(const AExpression: IExpression): TValue;
begin
  if AExpression = nil then Exit(TValue.Empty);

  if AExpression is TPropertyExpression then
    Result := GetPropertyValue(TPropertyExpression(AExpression).PropertyName)
  else if AExpression is TLiteralExpression then
    Result := TLiteralExpression(AExpression).Value
  else if AExpression is TArithmeticExpression then
  begin
    Result := Calculate(ResolveValue(TArithmeticExpression(AExpression).Left), 
                        ResolveValue(TArithmeticExpression(AExpression).Right), 
                        TArithmeticExpression(AExpression).ArithmeticOperator);
  end
  else
    Result := TValue.Empty;
end;

function TEvaluatorVisitor.Compare(const Left, Right: TValue; Op: TBinaryOperator): Boolean;
var
  L, R: Variant;
  I: Integer;
  Elem: TValue;
begin
  if Left.IsEmpty or Right.IsEmpty then
  begin
    // Handle nulls
    case Op of
      boEqual: Result := Left.IsEmpty and Right.IsEmpty;
      boNotEqual: Result := not (Left.IsEmpty and Right.IsEmpty);
      else Result := False;
    end;
    Exit;
  end;

  L := Left.AsVariant;
  R := Right.AsVariant;

  case Op of
    boEqual: Result := L = R;
    boNotEqual: Result := L <> R;
    boGreaterThan: Result := L > R;
    boGreaterThanOrEqual: Result := L >= R;
    boLessThan: Result := L < R;
    boLessThanOrEqual: Result := L <= R;
    // Case-insensitive, as before. % and _ are wildcards anywhere in the
    // pattern, as in SQL.
    boLike: Result := LikeMatches(VarToStr(L), VarToStr(R), True);
    boNotLike: Result := not Compare(Left, Right, boLike);
    // The value is matched literally: a % or _ in it is not a wildcard.
    boStartsWith: Result := VarToStr(L).ToLower.StartsWith(VarToStr(R).ToLower);
    boEndsWith: Result := VarToStr(L).ToLower.EndsWith(VarToStr(R).ToLower);
    boContains: Result := VarToStr(L).ToLower.Contains(VarToStr(R).ToLower);
    boIn: 
      begin
        Result := False;
        if Right.IsArray then
        begin
          for I := 0 to Right.GetArrayLength - 1 do
          begin
            Elem := Right.GetArrayElement(I);
            if Compare(Left, Elem, boEqual) then
            begin
              Result := True;
              Break;
            end;
          end;
        end;
      end;
    boNotIn: Result := not Compare(Left, Right, boIn);
    boBitwiseAnd: Result := (Integer(L) and Integer(R)) <> 0;
    boBitwiseOr: Result := (Integer(L) or Integer(R)) <> 0;
    boBitwiseXor: Result := (Integer(L) xor Integer(R)) <> 0;
    else Result := False;
  end;
end;

function TEvaluatorVisitor.Calculate(const Left, Right: TValue; Op: TArithmeticOperator): TValue;
var
  L, R: Variant;
begin
  L := Left.AsVariant;
  R := Right.AsVariant;
  case Op of
    aoAdd: Result := TValue.FromVariant(L + R);
    aoSubtract: Result := TValue.FromVariant(L - R);
    aoMultiply: Result := TValue.FromVariant(L * R);
    aoDivide: Result := TValue.FromVariant(L / R);
    aoModulus: Result := TValue.FromVariant(L mod R);
    aoIntDivide: Result := TValue.FromVariant(L div R);
    else Result := TValue.Empty;
  end;
end;

procedure TEvaluatorVisitor.Visit(const AExpression: IExpression);
var
  Bin: TBinaryExpression;
  L, R: TValue;
  Log: TLogicalExpression;
  LeftRes, RightRes: Boolean;
  Un: TUnaryExpression;
  Val: TValue;
begin
  if AExpression is TBinaryExpression then
  begin
    Bin := TBinaryExpression(AExpression);
    L := ResolveValue(Bin.Left);
    R := ResolveValue(Bin.Right);
    FResult := Compare(L, R, Bin.BinaryOperator);
  end
  else if AExpression is TLogicalExpression then
  begin
    Log := TLogicalExpression(AExpression);
    
    // Visit Left
    Visit(Log.Left);
    LeftRes := FResult;
    
    // Short-circuit
    if (Log.LogicalOperator = loAnd) and (not LeftRes) then
    begin
      FResult := False;
      Exit;
    end;
    if (Log.LogicalOperator = loOr) and (LeftRes) then
    begin
      FResult := True;
      Exit;
    end;
    
    // Visit Right
    Visit(Log.Right);
    RightRes := FResult;
    
    if Log.LogicalOperator = loAnd then
      FResult := LeftRes and RightRes
    else
      FResult := LeftRes or RightRes;
  end
  else if AExpression is TUnaryExpression then
  begin
    Un := TUnaryExpression(AExpression);
    if Un.UnaryOperator = uoNot then
    begin
      Visit(Un.Expression);
      FResult := not FResult;
    end
    else if Un.UnaryOperator = uoIsNull then
    begin
      Val := GetPropertyValue(Un.PropertyName);
      FResult := Val.IsEmpty or (Val.Kind = tkClass) and (Val.AsObject = nil) or (Val.Kind = tkInterface) and (Val.AsInterface = nil);
    end
    else if Un.UnaryOperator = uoIsNotNull then
    begin
      Val := GetPropertyValue(Un.PropertyName);
      FResult := not (Val.IsEmpty or (Val.Kind = tkClass) and (Val.AsObject = nil) or (Val.Kind = tkInterface) and (Val.AsInterface = nil));
    end;
  end
  else if AExpression is TConstantExpression then
  begin
    FResult := TConstantExpression(AExpression).Value;
  end;
end;

end.


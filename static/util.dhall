let MkReferenceType = λ(a : Type) → < Ref : Text | Val : a >

let TextR = MkReferenceType Text

let NaturalR = MkReferenceType Natural

let IntegerR = MkReferenceType Integer

let BoolR = MkReferenceType Bool

let DoubleR = MkReferenceType Double

let TagType = { mapKey : Text, mapValue : Text }

let mkTag = λ(k : Text) → λ(v : Text) → { mapKey = k, mapValue = v }

in  { RefVal =
      { Type = MkReferenceType
      , Text = TextR
      , Natural = NaturalR
      , Integer = IntegerR
      , Bool = BoolR
      , Double = DoubleR
      }
    , Tag = { Type = TagType, mk = mkTag }
    , Tags.Type = List TagType
    , t = TextR.Val
    , st = λ(x : Text) → Some (TextR.Val x)
    , n = NaturalR.Val
    , sn = λ(x : Natural) → Some (NaturalR.Val x)
    , i = IntegerR.Val
    , si = λ(x : Integer) → Some (IntegerR.Val x)
    , b = BoolR.Val
    , sb = λ(x : Bool) → Some (BoolR.Val x)
    , d = DoubleR.Val
    , sd = λ(x : Double) → Some (DoubleR.Val x)
    , Res =
      { Type = λ(a : Type) → { mapKey : Text, mapValue : a }
      , mk =
          λ(a : Type) →
          λ(name : Text) →
          λ(x : a) →
            { mapKey = name, mapValue = x }
      }
    }

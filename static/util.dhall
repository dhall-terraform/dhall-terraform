let MkReferenceType = λ(a : Type) → < Ref : Text | Val : a >

let TextR = MkReferenceType Text

let NaturalR = MkReferenceType Natural

let IntegerR = MkReferenceType Integer

let BoolR = MkReferenceType Bool

let DoubleR = MkReferenceType Double

let TagType = { mapKey : Text, mapValue : Text }

let mkTag = λ(k : Text) → λ(v : Text) → { mapKey = k, mapValue = v }

in  { Reference =
      { MkType = MkReferenceType
      , Text = TextR
      , Natural = NaturalR
      , Integer = IntegerR
      , Bool = BoolR
      , Double = DoubleR
      }
    , Tag = { Type = TagType, mk = mkTag }
    , Tags.Type = List TagType
    , t = TextR.Val
    , n = NaturalR.Val
    , i = IntegerR.Val
    , b = BoolR.Val
    , d = DoubleR.Val
    , mkResT =
        λ(a : Type) →
        λ(name : Text) →
        λ(x : a) →
          { mapKey = name, mapValue = x }
    , Res.Type = λ(a : Type) → { mapKey : Text, mapValue : a }
    }

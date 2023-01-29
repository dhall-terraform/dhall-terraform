let MkReferenceType = \(a : Type) -> < Ref : Text | Val : a >

let TextR = MkReferenceType Text

let NaturalR = MkReferenceType Natural

let IntegerR = MkReferenceType Integer

let BoolR = MkReferenceType Bool

let DoubleR = MkReferenceType Double

let TagType = { mapKey : Text, mapValue : Text }

let mkTag = \(k : Text) -> \(v : Text) -> { mapKey = k, mapValue = v }

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
    }

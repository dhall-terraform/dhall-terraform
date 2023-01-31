{-# LANGUAGE OverloadedStrings #-}

module Main
  ( main,
  )
where

import Data.Bifunctor (second)
import qualified Data.Text.IO as TIO
import Control.Concurrent.Async (mapConcurrently_)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as B
import Data.Map.Strict (Map, (!))
import Data.List.NonEmpty(NonEmpty(..))
import qualified Data.Map.Strict as M
import Data.Maybe (fromJust, fromMaybe)
import Data.Text (Text, pack, unpack)
import qualified Prettyprinter as Pretty
import qualified Prettyprinter.Render.Text as PrettyText
import Data.Version (showVersion)
import qualified Dhall.Core as Dhall
import Dhall.Format (Format (..), format)
import qualified Dhall.Map
import qualified Dhall.Pretty
import qualified Dhall.Util
import qualified Options.Applicative as Opt
import Paths_dhall_terraform (version)
import Terraform.Convert
import Terraform.Types
import Turtle ((</>))
import qualified Turtle

-- | Pretty print dhall expressions.
pretty :: Pretty.Pretty a => a -> Text
pretty =
  PrettyText.renderStrict
    . Pretty.layoutPretty Pretty.defaultLayoutOptions
    . Pretty.pretty

-- | Reads a JSON file that contains the schema definitions of a Terraform provider.
readSchemaFile :: FilePath -> IO ProviderSchemaRepr
readSchemaFile f = do
  doc <- (Aeson.eitherDecode <$> B.readFile f) :: IO (Either String ProviderSchemaRepr)
  case doc of
    Left e -> error e
    Right d -> pure d

getResources :: Text -> ProviderSchemaRepr -> Map Text SchemaRepr
getResources name schema = fromJust $ _resourceSchemas (_providerSchemas schema ! name)

getProvider :: Text -> ProviderSchemaRepr -> Map Text SchemaRepr
getProvider name schema =
  let provider = fromJust $ _provider (_providerSchemas schema ! name)
   in M.fromList [("provider", provider)]

getDataSources :: Text -> ProviderSchemaRepr -> Map Text SchemaRepr
getDataSources name schema = fromJust $ _dataSourceSchemas (_providerSchemas schema ! name)

-- | Write and format a Dhall expression to a file
writeDhall :: Turtle.FilePath -> Expr -> IO ()
writeDhall filepath expr = do
  putStrLn $ "Writing file '" <> Turtle.encodeString filepath <> "'"
  TIO.writeFile filepath $ pretty expr <> "\n"
  format
    ( Format
        { chosenCharacterSet = Just Dhall.Pretty.ASCII,
          censor = Dhall.Util.NoCensor,
          outputMode = Dhall.Util.Write,
          transitivity = Dhall.Util.Transitive,
          inputs = Dhall.Util.InputFile filepath :| []
        }
    )

data TFType =
    TFProvider
  | TFResource
  | TFData

tfTypeToText :: TFType -> Text
tfTypeToText TFProvider = "provider"
tfTypeToText TFResource = "resource"
tfTypeToText TFData = "data"

type ProviderType = Text

-- | Generate a completion record for the resource.
mkRecord :: TFType -> Turtle.FilePath -> ProviderType -> BlockRepr -> IO ()
mkRecord ty rootPath name block = do
  let recordPath = rootPath </> Turtle.fromText (name <> ".dhall")
      utilImport =
        Dhall.Import
        (Dhall.ImportHashed
          Nothing
          (Dhall.Local Dhall.Here (Dhall.File (Dhall.Directory ["static", "..", "..", "..", "..", ".."]) "util.dhall")))
        Dhall.Code
      record =
        Dhall.Let
          (Dhall.makeBinding "Util" (Dhall.Embed utilImport)) $
          Dhall.Let
            (Dhall.makeBinding "type" (mkBlockFields block)) $
            Dhall.Let
              (Dhall.makeBinding "show" (mkBlockShowField block)) $
              Dhall.Let
                (Dhall.makeBinding "typeOf" (mkBlockTypeOfField block)) $
                Dhall.Let
                  (Dhall.makeBinding "T" (mkBlockType block)) $
                  Dhall.RecordLit $
                    Dhall.makeRecordField
                      <$> Dhall.Map.fromList
                        [ ("Type", bigTypeVar)
                        , ("default", mkBlockDefault block)
                        , ("Fields", typeVar)
                        , ("showField", showVar)
                        , ("typeOfField", typeOfVar)
                        , ("ref", mkBlockRef "Ref" name ty block)
                        , ("val", mkBlockRef "Val" name ty block)
                        , ("mkRes", mkBlockMkRes name block)
                        ]
  Turtle.mktree rootPath
  writeDhall recordPath record
  where
    bigTypeVar :: Dhall.Expr s a
    bigTypeVar = Dhall.Var $ Dhall.V "T" 0

    typeVar :: Dhall.Expr s a
    typeVar = Dhall.Var $ Dhall.V "type" 0

    showVar :: Dhall.Expr s a
    showVar = Dhall.Var $ Dhall.V "show" 0

    typeOfVar :: Dhall.Expr s a
    typeOfVar = Dhall.Var $ Dhall.V "typeOf" 0

    underOptional :: (Dhall.Expr s a -> Dhall.Expr s a) -> Dhall.Expr s a -> Dhall.Expr s a
    underOptional k (Dhall.App Dhall.Optional t) = Dhall.App Dhall.Optional (k t)
    underOptional k expr = k expr

    stripOptional :: Dhall.Expr s a -> Dhall.Expr s a
    stripOptional (Dhall.App Dhall.Optional t) = t
    stripOptional expr = expr

    util = Dhall.Var $ Dhall.V "Util" 0

    utilMkReferenceTypeVar :: Dhall.Expr s a
    utilMkReferenceTypeVar = Dhall.Field (Dhall.Field util (Dhall.makeFieldSelection "Reference")) (Dhall.makeFieldSelection "MkType")

    appMkRefType = Dhall.App utilMkReferenceTypeVar

    mkRefType = underOptional appMkRefType

    mkBlockType :: BlockRepr -> Expr
    mkBlockType b =
      Dhall.Record
      $ Dhall.makeRecordField
      <$> Dhall.Map.fromList (fmap mkRefType <$> (typeAttrs b <> typeNested b))

    mkBlockDefault :: BlockRepr -> Expr
    mkBlockDefault b = Dhall.RecordLit $ Dhall.makeRecordField <$> Dhall.Map.fromList (defAttrs b <> defNested b)

    mkBlockFields :: BlockRepr -> Expr
    mkBlockFields b = Dhall.Union $ Nothing <$ Dhall.Map.fromList (typeAttrs b <> typeNested b)

    mkBlockTypeOfField :: BlockRepr -> Expr
    mkBlockTypeOfField b =
      Dhall.Lam
         Nothing
         (Dhall.makeFunctionBinding "x" typeVar)
         (Dhall.Merge
           (Dhall.RecordLit $
             Dhall.Map.fromList $
             second Dhall.makeRecordField . fmap stripOptional <$>
            (typeAttrs b <> typeNested b))
           (Dhall.Var $ Dhall.V "x" 0)
           Nothing)

    mkBlockShowField :: BlockRepr -> Expr
    mkBlockShowField b =
      Dhall.Lam
         Nothing
         (Dhall.makeFunctionBinding "x" typeVar)
         (Dhall.Merge
           (Dhall.RecordLit $
             Dhall.Map.fromList $
            (\(nm, _) -> (nm, Dhall.makeRecordField $ Dhall.TextLit (Dhall.Chunks [] nm))) <$>
            (typeAttrs b <> typeNested b))
           (Dhall.Var $ Dhall.V "x" 0)
           Nothing)

    -- | Select the @Val@ or @Ref@ constructor of the Union, depending on
    -- @valOrRef@
    mkBlockRef :: Text -> ProviderType -> TFType -> BlockRepr -> Expr
    mkBlockRef valOrRef p t _ =
      Dhall.Lam
        Nothing
        (Dhall.makeFunctionBinding "field" typeVar) $
        case valOrRef of
           "Ref" ->
             Dhall.Lam
               Nothing
               (Dhall.makeFunctionBinding "name" Dhall.Text)
               (Dhall.App ref
                 (Dhall.TextLit (Dhall.Chunks [ ("${" <> tfTypeToText t <> "." <> p <> ".", Dhall.Var $ Dhall.V "name" 0)
                                              , (".", Dhall.App showVar $ Dhall.Var $ Dhall.V "field" 0)
                                              ] "}")))
           _ -> ref
      where
        referenceType = Dhall.App utilMkReferenceTypeVar (Dhall.App typeOfVar (Dhall.Var $ Dhall.V "field" 0))
        ref = Dhall.Field referenceType (Dhall.makeFieldSelection valOrRef)

    mkBlockMkRes :: Text -> BlockRepr -> Expr
    mkBlockMkRes name b =
        Dhall.Lam
          Nothing
          (Dhall.makeFunctionBinding "name" Dhall.Text) $
            Dhall.Lam
              Nothing
              (Dhall.makeFunctionBinding "x" bigTypeVar) $
                Dhall.App
                  (Dhall.App
                    (Dhall.App
                       (Dhall.Field util (Dhall.makeFieldSelection "mkResT"))
                       bigTypeVar)
                    (Dhall.Var $ Dhall.V "name" 0))
                  (Dhall.Var $ Dhall.V "x" 0)

    defAttrs = attrs (toDefault . mkRefType)
    typeAttrs = attrs Just

    defNested = nested (toDefault . mkRefType)
    typeNested = nested Just

    attrs :: (Expr -> Maybe a) -> BlockRepr -> [(Text, a)]
    attrs mapExpr b =
      M.toList $
        M.mapMaybe mapExpr $
          M.map attrToType (fromMaybe noAttrs $ _attributes b)

    nested :: (Expr -> Maybe a) -> BlockRepr -> [(Text, a)]
    nested mapExpr b =
      M.toList $
        M.mapMaybe mapExpr $
          M.map nestedToType (fromMaybe noNestedBlocks $ _blockTypes b)

generate :: TFType -> Turtle.FilePath -> Map Text SchemaRepr -> IO ()
generate ty rootDir schemas =
  mapM_
    (uncurry (mkRecord ty rootDir))
    blocks
  where
    blocks = M.toList $ M.map _schemaReprBlock schemas

data CliOpts = CliOpts
  { optSchemaFile :: String,
    optProviderName :: String,
    optOutputDir :: String
  }
  deriving (Show, Eq)

cliOpts :: Opt.Parser CliOpts
cliOpts =
  CliOpts
    <$> Opt.strOption
      ( Opt.long "schema-file"
          <> Opt.short 'f'
          <> Opt.help "Terraform provider's schema definitions"
          <> Opt.metavar "SCHEMA"
      )
    <*> Opt.strOption
      ( Opt.long "provider-name"
          <> Opt.short 'p'
          <> Opt.help "Which provider's resources will be generated"
          <> Opt.metavar "PROVIDER"
      )
    <*> Opt.strOption
      ( Opt.long "output-dir"
          <> Opt.short 'o'
          <> Opt.help "The directory to store the generated files"
          <> Opt.metavar "OUT_DIR"
          <> Opt.showDefault
          <> Opt.value "./lib"
      )

opts :: Opt.ParserInfo CliOpts
opts =
  Opt.info
    (Opt.helper <*> cliOpts)
    ( Opt.fullDesc
        <> Opt.progDesc "Generate Dhall types from Terraform resources"
        <> Opt.header ("dhall-terraform-libgen :: v" <> showVersion version)
    )

main :: IO ()
main = do
  parsedOpts <- Opt.execParser opts

  let outputDir = Turtle.fromText $ pack $ optOutputDir parsedOpts
      providerName = pack $ optProviderName parsedOpts
      mainDir = outputDir </> Turtle.fromText providerName
      providerDir = mainDir </> Turtle.fromText "provider"
      resourcesDir = mainDir </> Turtle.fromText "resources"
      dataSourcesDir = mainDir </> Turtle.fromText "data_sources"
      schema_generator = uncurry (uncurry generate)

  doc <- readSchemaFile (optSchemaFile parsedOpts)

  let generateDirs =
        [ ((TFProvider, providerDir), getProvider providerName doc),
          ((TFResource, resourcesDir), getResources providerName doc),
          ((TFData, dataSourcesDir), getDataSources providerName doc)
        ]

  mapConcurrently_ schema_generator generateDirs

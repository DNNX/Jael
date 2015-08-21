{-# Language NoImplicitPrelude #-}

import ClassyPrelude
import Test.Framework

import Test.Jael.Grammar.Enum (gEnumTests)
import Test.Jael.Grammar.Expr (gExprTests)
import Test.Jael.Grammar.Struct (gStructTests)
import Test.Jael.Grammar.Type (gTypeTests)
import Test.Jael.Seq.AST (astTests)
import Test.Jael.Seq.Enum (enumTests)
import Test.Jael.Seq.Struct (structTests)
import Test.Jael.Seq.TI (seqInfTests)

main :: IO ()
main = defaultMainWithOpts [ testGroup "Enum grammar" gEnumTests
                           , testGroup "Expr grammar" gExprTests
                           , testGroup "Struct grammar" gStructTests
                           , testGroup "Type grammar" gTypeTests
                           , testGroup "AST tests" astTests
                           , testGroup "Enum creation" enumTests
                           , testGroup "Struct creation" structTests
                           , testGroup "Seq type inference" seqInfTests
                           ] mempty


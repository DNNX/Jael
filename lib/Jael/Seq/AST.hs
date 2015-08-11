{-# Language NoImplicitPrelude, TypeSynonymInstances, FlexibleInstances #-}

-- Implementation based off of https://github.com/wh5a/Algorithm-W-Step-By-Step

module Jael.Seq.AST where

import ClassyPrelude
import qualified Data.Map as M
import qualified Data.Set as S
import Text.Read (reads)
import Jael.Grammar

data Ex = EVar Text
        | ELit ExLit
        | ETup ExTup
        | EApp Ex Ex
        | EAbs Text Ex
        | ELet Text Ex Ex
          deriving (Show)

data ExLit  = LInt Integer
            | LBool Bool
              deriving (Show)

data ExTup = ExTup Ex ExTup
           | EUnit
             deriving (Show)

data Ty = TVar Text
        | TInt
        | TBool
        | TTup TyTup
        | TFun Ty Ty
          deriving (Eq, Show)

data TyTup = TyTup (Ty, Maybe Text) TyTup
           | TUnit
           deriving (Eq, Show)

data PolyTy = PolyTy [Text] Ty
              deriving (Show)

type TyEnv = M.Map Text PolyTy

builtinTypes :: TyEnv
builtinTypes = M.fromList
  [ ( "if" -- Bool -> a -> a -> a
    , PolyTy ["a"] (TFun TBool (TFun (TVar "a") (TFun (TVar "a") (TVar "a"))))
    )
  , ( "<$" -- (a -> b) -> a -> b
    , PolyTy ["a", "b"] (TFun (TFun (TVar "a") (TVar "b")) (TFun (TVar "a") (TVar "b")))
    )
  , ( "$>" -- a -> (a -> b) -> b
    , PolyTy ["a", "b"] (TFun (TVar "a") (TFun (TFun (TVar "a") (TVar "b")) (TVar "b")))
    )
  , ( "||"
    , PolyTy [] (TFun TBool (TFun TBool TBool))
    )
  , ( "&&"
    , PolyTy [] (TFun TBool (TFun TBool TBool))
    )
  , ( "=="
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") TBool))
    )
  , ( "!="
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") TBool))
    )
  , ( ">="
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") TBool))
    )
  , ( "<="
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") TBool))
    )
  , ( ">"
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") TBool))
    )
  , ( "<"
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") TBool))
    )
  , ( "+"
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") (TVar "a")))
    )
  , ( "-"
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") (TVar "a")))
    )
  , ( "*"
    , PolyTy ["a"] (TFun (TVar "a") (TFun (TVar "a") (TVar "a")))
    )
  , ( "/"
    , PolyTy [] (TFun TInt (TFun TInt (TTup (TyTup (TInt, Just "quot") (TyTup (TInt, Just "rem") TUnit)))))
    )
  , ( "%"
    , PolyTy [] (TFun TInt (TFun TInt TInt))
    )
  , ( "<o" -- (b -> c) -> (a -> b) -> (a -> c)
    , PolyTy ["a", "b", "c"] (TFun (TFun (TVar "b") (TVar "c")) (TFun (TFun (TVar "a") (TVar "b")) (TFun (TVar "a") (TVar "c"))))
    )
  , ( "o>" -- (a -> b) -> (b -> c) -> (a -> c)
    , PolyTy ["a", "b", "c"] (TFun (TFun (TVar "a") (TVar "b")) (TFun (TFun (TVar "b") (TVar "c")) (TFun (TVar "a") (TVar "c"))))
    )
  , ( "!"
    , PolyTy ["a"] (TFun (TVar "a") (TVar "a"))
    )
  ]
type TySub = M.Map Text Ty

data SeqTIState = SeqTIState {
  tvCount :: Integer,
  tiErrors :: [Text]
}
newtype SeqTI a = SeqTI (SeqTIState -> (Maybe a, SeqTIState))

instance Monad SeqTI where
  (SeqTI p) >>= f = SeqTI $ \s -> case p s of
                                       (Just v,  s') -> let (SeqTI n) = f v
                                                        in  n s'
                                       (Nothing, s') -> (Nothing, s')
  return v = SeqTI $ \s -> (Just v, s)

instance Applicative SeqTI where
  pure = return
  (<*>) = ap

instance Functor SeqTI where
  fmap = liftM

seqInfer :: Ex -> Either [Text] Ty
seqInfer e = runSeqTI (seqTypeInference builtinTypes e)

runSeqTI :: SeqTI a -> Either [Text] a
runSeqTI t = let (SeqTI stateFunc) = t
                 initState = SeqTIState{ tvCount = 0, tiErrors = [] }
             in  case stateFunc initState of
                      (Just v,  s) -> Right v
                      (Nothing, s) -> Left $ tiErrors s

seqTypeInference :: TyEnv -> Ex -> SeqTI Ty
seqTypeInference env e = do
  (sub, ty) <- ti env e
  return $ apply sub ty

getTvCount :: SeqTI Integer
getTvCount = SeqTI $ \s -> (Just (tvCount s), s)

incTvCount :: SeqTI ()
incTvCount = SeqTI $ \s -> (Just (), s{tvCount = (tvCount s) + 1})

newTV :: SeqTI Ty
newTV = getTvCount >>= (\i -> (>>) incTvCount $ return . TVar $ "a" ++ tshow i)

getTiErrors :: SeqTI [Text]
getTiErrors = SeqTI $ \s -> (Just $ tiErrors s, s)

putTiErrors :: [Text] -> SeqTI ()
putTiErrors ts = SeqTI $ \s -> (Just (), s{tiErrors=ts})

-- Halts inference and records the error
tiError :: Text -> SeqTI a
tiError t = getTiErrors >>= (\ts -> putTiErrors $ t:ts) >> (SeqTI $ \s -> (Nothing, s))

class TyOps a where
  ftv :: a -> S.Set Text
  apply :: TySub -> a -> a

instance TyOps Ty where
  ftv (TVar t)     = S.singleton t
  ftv TInt         = S.empty
  ftv TBool        = S.empty
  ftv (TFun t1 t2) = (ftv t1) `S.union` (ftv t2)
  ftv (TTup t)     = (ftv t)

  apply s t@(TVar v) =
    case M.lookup v s of
      Nothing   -> t
      Just newt -> newt
  apply s (TFun t1 t2) = TFun (apply s t1) (apply s t2)
  apply s (TTup t) = TTup (apply s t)
  apply _ t = t

instance TyOps TyTup where
  ftv (TyTup (t1, x) t2) = (ftv t2) `S.union` (ftv t2)
  ftv TUnit = S.empty

  apply s (TyTup (t1, x) t2) = TyTup (apply s t1, x) (apply s t2)
  apply _ TUnit = TUnit

instance TyOps PolyTy where
  -- Free type variables of a type scheme are the ones not bound by a universal
  -- quantifier. I.e., the type variables within t not in vs
  ftv (PolyTy vs t) = (ftv t) `S.difference` (S.fromList vs)
  -- This first deletes the variables of the scheme from the substitution then
  -- applies the substitution
  apply s (PolyTy vs t) = PolyTy vs (apply (foldr M.delete s vs) t)

instance TyOps a => TyOps [a] where
  ftv ls = foldr S.union S.empty $ map ftv ls
  apply s ls = map (apply s) ls

instance TyOps TyEnv where
  ftv env = ftv $ M.elems env
  apply sub env = M.map (apply sub) env

remove :: TyEnv -> Text -> TyEnv
remove env t = M.delete t env

nullSub :: TySub
nullSub = M.empty

compSub :: TySub -> TySub -> TySub
compSub a b = M.union (M.map (apply a) b) a

-- Creates a scheme from a type by adding the qualified type variables of the
-- environment
generalization :: TyEnv -> Ty -> PolyTy
generalization env t = PolyTy (S.toList $ ftv t `S.difference` ftv env) t

-- Creates a type from a scheme by making new type variables and applying
-- a substituion from the old to the new
instantiation :: PolyTy -> SeqTI Ty
instantiation (PolyTy vs ty) = do
  nvs <- mapM (\_ -> newTV) vs
  return $ apply (M.fromList $ zip vs nvs) ty

-- Most general unifier. Used in the application rule for determining the return
-- type after application to a function
mgu :: Ty -> Ty -> Either Text TySub
mgu (TFun l1 r1) (TFun l2 r2) = do
  sub1 <- mgu l1 l2
  sub2 <- mgu (apply sub1 r1) (apply sub1 r2)
  return $ compSub sub1 sub2
mgu (TVar u) t = varBind u t
mgu t (TVar u) = varBind u t
mgu TInt    TInt    = Right nullSub
mgu TBool   TBool   = Right nullSub
mgu t1 t2 = Left $ "Types \"" ++ tshow t1 ++ "\" and \"" ++ tshow t2 ++ "\" do not unify."

varBind :: Text -> Ty -> Either Text TySub
varBind u t
  | t == TVar u        = Right nullSub
  | S.member u (ftv t) = Left $ "Can not bind \"" ++ tshow u ++ "\" to \""
      ++ tshow t ++ "\" because \"" ++ tshow u ++ "\" is a free type variable of \""
      ++ tshow t
  | otherwise          = Right $ M.singleton u t

ti :: TyEnv -> Ex -> SeqTI (TySub, Ty)
-- Literals
ti _ (ELit (LInt _))  = return (nullSub, TInt)
ti _ (ELit (LBool _)) = return (nullSub, TBool)
ti _ (ETup EUnit)          = return (nullSub, TTup TUnit)

-- Variables
ti env (EVar v) = do
  case M.lookup v env of
    Nothing -> tiError $ "unbound variable \"" ++ tshow v ++ "\""
    Just sigma -> do
       t <- instantiation sigma
       return (nullSub, t)

-- Function application
ti env (EApp e1 e2) = do
  tv <- newTV
  (sub1, t1) <- ti env e1
  (sub2, t2) <- ti (apply sub1 env) e2
  let sub3 = mgu (apply sub2 t1) (TFun t2 tv)
  case sub3 of
       Left err -> tiError (err ++ "\n\n"
                                ++ "Type variable : " ++ tshow tv ++ "\n\n"
                                ++ "Inference 1   : " ++ tshow (t1, sub1) ++ "\n"
                                ++ "   for expr   : " ++ tshow e1 ++ "\n\n"
                                ++ "Inference 2   : " ++ tshow (t2, sub2) ++ "\n"
                                ++ "   for expr   : " ++ tshow e2 ++ "\n\n"
                           )
       Right sub3 -> do
         return (sub1 `compSub` sub2 `compSub` sub3, apply sub3 tv)

-- Abstraction
ti env (EAbs x e) = do
  tv <- newTV
  let env' = remove env x
      env'' = env' `M.union` (M.singleton x (PolyTy [] tv))
  (s1, t1) <- ti env'' e
  return (s1, TFun (apply s1 tv) t1)

-- Let
ti env (ELet x e1 e2) = do
  (s1, t1) <- ti env e1
  let env' = remove env x
      t' = generalization (apply s1 env) t1
      env'' = M.insert x t' env'
  (s2, t2) <- ti (apply s1 env'') e2
  return (s1 `compSub` s2, t2)

-- The LetExpr grammar is only allowed in certain places so it isn't of the GExpr type
letExprToEx :: GELetExpr -> Ex
letExprToEx (GELetExpr [] e)    = toSeqEx e
-- i[dentifier]; h[ead] e[xpression]; t[ail] l[et expression]s; e[xpression]
letExprToEx (GELetExpr ((GELetIdent (LIdent i) he):tls) e) = ELet (pack i) (toSeqEx he) (letExprToEx $ GELetExpr tls e)

myIntegerErrorMsg :: String
myIntegerErrorMsg = "Lexer should not produce MyInteger that " ++
                    "can't be parsed. See definition in Grammar.cf"

parseInt :: IntTok -> Integer
parseInt (IntTok []) = error myIntegerErrorMsg
parseInt (IntTok s@(x:xs)) = let bNeg = x == '~'
                                 readRes = if bNeg
                                              then reads xs
                                              else reads s
                             in  case readRes of
                                      [(i, [])] -> if bNeg then -i else i
                                      _         -> error myIntegerErrorMsg

-- Helper function to apply arguments to an expression
applyArgs :: Ex -> [GEAppArg] -> Ex
applyArgs e ((GEAppArg a):[]) = EApp e (toSeqEx a)
applyArgs e ((GEAppArg a):as) = applyArgs (EApp e (toSeqEx a)) as

-- Converts grammar to AST but does not verify its correctness
toSeqEx :: GExpr -> Ex

toSeqEx (GEPlus  e1 e2) = EApp (EApp (EVar "+") (toSeqEx e1)) (toSeqEx e2)
toSeqEx (GEMinus e1 e2) = EApp (EApp (EVar "-") (toSeqEx e1)) (toSeqEx e2)
toSeqEx (GETimes e1 e2) = EApp (EApp (EVar "*") (toSeqEx e1)) (toSeqEx e2)

toSeqEx (GELogNot e) = EApp (EVar "!") (toSeqEx e)

toSeqEx (GEIf b e1 e2) = EApp (EApp (EApp (EVar "if") (toSeqEx b)) (letExprToEx e1)) (letExprToEx e2)

toSeqEx (GEApp e []) = error "Application without arguments should be forbidden by the grammar."
toSeqEx (GEApp e as) = applyArgs (toSeqEx e) as

toSeqEx (GEAbs [] le) = error "Lambda without arguments should be forbidden by the grammar."
toSeqEx (GEAbs ((GEAbsArg (LIdent i)):[]) le) = EAbs (pack i) (letExprToEx le)
toSeqEx (GEAbs ((GEAbsArg (LIdent i)):xs) le) = EAbs (pack i) (toSeqEx $ GEAbs xs le)

toSeqEx (GEVar (LIdent i)) = EVar (pack i)

toSeqEx (GEInt i) = ELit (LInt $ parseInt i)

toSeqEx (GETrue)  = ELit (LBool True)
toSeqEx (GEFalse) = ELit (LBool False)

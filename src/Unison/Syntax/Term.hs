{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE Rank2Types #-}

module Unison.Syntax.Term where

import Control.Monad
import qualified Data.Set as S
import qualified Data.Text as Txt
import qualified Data.Vector.Unboxed as V
import Unison.Syntax.Var as V
import qualified Unison.Syntax.Hash as H
import qualified Unison.Syntax.Type as T

-- | Literals in the Unison language
data Literal
  = Number Double
  | String Txt.Text
  | Vector (V.Vector Double)
  deriving (Eq,Ord,Show,Read)

-- | Terms in the Unison language
data Term
  = Var V.Var
  | Lit Literal
  | Con H.Hash -- ^ A constructor reference. @Con h `App` ...@ is by definition in normal form
  | Ref H.Hash
  | App Term Term
  | Ann Term T.Type
  | Lam V.Var Term
  deriving (Eq,Ord)

instance Show Term where
  show (Var v) = show v
  show (Ref v) = show v
  show (Lit l) = show l
  show (Con h) = show h
  show (App f x@(App _ _)) = show f ++ "(" ++ show x ++ ")"
  show (App f x) = show f ++ " " ++ show x
  show (Ann x t) = "(" ++ show x ++ " : " ++ show t ++ ")"
  show (Lam n body) = "(" ++ show n ++ " -> " ++ show body ++ ")"

maxV :: Term -> V.Var
maxV (App f x) = maxV f `max` maxV x
maxV (Ann x _) = maxV x
maxV (Lam n _) = n
maxV _         = V.decr V.bound1

lam1M :: Monad f => (Term -> f Term) -> f Term
lam1M f = return Lam `ap` n `ap` body
  where
    n               = liftM (V.succ . maxV) body
    body            = f =<< (liftM Var n)

lam1 :: (Term -> Term) -> Term
lam1 f = Lam n body
  where
    n = V.succ (maxV body)
    body = f (Var n)

lam2 :: (Term -> Term -> Term) -> Term
lam2 f = lam1 $ \x -> lam1 $ \y -> f x y

lam3 :: (Term -> Term -> Term -> Term) -> Term
lam3 f = lam1 $ \x -> lam1 $ \y -> lam1 $ \z -> f x y z

{-
collect :: Applicative f
       => (V.Var -> f Term)
       -> Term
       -> f Term
collect f = go where
  go e = case e of
    Var v -> f v
    Ref h -> pure (Ref h)
    Con h -> pure (Con h)
    Lit l -> pure (Lit l)
    App fn arg -> App <$> go fn <*> go arg
    Ann e' t -> Ann <$> go e' <*> pure t
    Lam n body -> lam1 $ \x -> Lam n <$> go body
-}

dependencies :: Term -> S.Set H.Hash
dependencies e = case e of
  Ref h -> S.singleton h
  Con h -> S.singleton h
  Var _ -> S.empty
  Lit _ -> S.empty
  App fn arg -> dependencies fn `S.union` dependencies arg
  Ann e _ -> dependencies e
  Lam _ body -> dependencies body

{-
vars :: Term -> [V.Var]
vars e = getConst $ collect (\v -> Const [v]) e
-}

stripAnn :: Term -> (Term, Term -> Term)
stripAnn (Ann e t) = (e, \e' -> Ann e' t)
stripAnn e = (e, id)

-- arguments 'f x y z' == '[x, y, z]'
arguments :: Term -> [Term]
arguments (App f x) = arguments f ++ [x]
arguments _ = []

-- | If the outermost term is a function application,
-- perform substitution of the argument into the body
betaReduce :: Term -> Term
betaReduce (App (Lam var f) arg) = go f where
  go :: Term -> Term
  go body = case body of
    App f x -> App (go f) (go x)
    Ann body t -> Ann (go body) t
    Lam n body -> Lam n (go body)
    Var v | v == var -> arg
    _ -> body
betaReduce e = e

applyN :: Term -> [Term] -> Term
applyN f = foldl App f

number :: Double -> Term
number n = Lit (Number n)

string :: String -> Term
string s = Lit (String (Txt.pack s))

text :: Txt.Text -> Term
text s = Lit (String s)

-- | Computes the nameless hash of the given term
hash :: Term -> H.Digest
hash _ = error "todo: Term.hash"

finalizeHash :: Term -> H.Hash
finalizeHash = H.finalize . hash

-- | Computes the nameless hash of the given terms, where
-- the terms may have mutual dependencies
hashes :: [Term] -> [H.Hash]
hashes _ = error "todo: Term.hashes"

hashLit :: Literal -> H.Digest
hashLit (Number n) = H.zero `H.append` H.double n
hashLit (String s) = H.one `H.append` H.text s
hashLit (Vector vec) = H.two `H.append` go vec where
  go _ = error "todo: hashLit vector"

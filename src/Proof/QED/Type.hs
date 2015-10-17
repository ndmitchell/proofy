{-# LANGUAGE GeneralizedNewtypeDeriving, BangPatterns #-}

module Proof.QED.Type(
    Known(..), Unknown(..), Goal(..), Side(..),
    QED, getKnown, qed,
    addDefinition, addType, addAssumed, addProved,
    Proof, getUnknown, getGoal, setFocusSide, setFocusAt,
    unsafeReplaceFirstGoal,
    Bind, addBind, runBind,
    Laws(..)
    ) where

import Control.Monad.Trans.State
import Control.Monad.Trans.Reader
import Control.Monad.Trans.Writer
import Control.Monad.Trans.Class
import Control.Monad.Catch
import Control.Monad.IO.Class
import Control.Exception
import Control.DeepSeq
import Control.Monad
import Proof.Util
import Proof.Exp.Core
import Proof.Exp.Prop

newtype Laws = Laws [Prop]
    deriving Monoid


---------------------------------------------------------------------
-- KNOWN STATE

newtype QED a = QED (StateT Known IO a)
    deriving (Functor, Applicative, Monad, MonadIO)

qed :: QED a -> IO ()
qed (QED x) = void $ execStateT x (Known [] builtinTypes [] [])

builtinTypes :: [(String,[(Con,Int)])]
builtinTypes =
    [("[]",[(C "[]",0),(C ":",2)])]

-- | All these things are append only
data Known = Known
    {definitions :: [(Var, Exp)]
    ,types :: [(String, [(Con,Int)])]
    ,assumed :: [Prop]
    ,proved :: [Prop]
    } deriving Show

instance NFData Known where
    rnf (Known a b c d) = rnf (a,b,c,d)

getKnown :: QED Known
getKnown = QED get

modifyKnown :: (Known -> Known) -> QED ()
modifyKnown f = QED $ do
    x <- get
    x <- return $ f x
    liftIO $ evaluate $ rnf x
    put x

addDefinition :: Var -> Exp -> QED ()
addDefinition a b = modifyKnown $ \s -> s{definitions = definitions s ++ [(a,b)]}

addType :: String -> [(Con,Int)] -> QED ()
addType a b = modifyKnown $ \s -> s{types = types s ++ [(a,b)]}

addAssumed :: Prop -> QED ()
addAssumed a = modifyKnown $ \s -> s{assumed = assumed s ++ [a]}

addProved :: Prop -> Proof () -> QED ()
addProved prop (Proof proof) = do
    known <- QED get
    let unknown = Unknown [Goal [] prop] Nothing 0
    unknown <- liftIO $ proof `runReaderT` known `execStateT` unknown
    unless (null $ goals unknown) $ do
        fail $ "Did not prove goal\n" ++ show (goals unknown)
    modifyKnown $ \s -> s{proved = proved s ++ [prop]}
    liftIO $ putStrLn $ show prop ++ "QED"


---------------------------------------------------------------------
-- UNKNOWN STATE

data Unknown = Unknown
    {goals :: [Goal] -- A list of And alternatives
    ,focusSide :: Maybe Side
    ,focusAt :: Int
    } deriving Show

data Side = LHS | RHS deriving (Show,Eq)

data Goal = Goal [Prop] Prop deriving Show

instance NFData Unknown where
    rnf (Unknown a b c) = rnf3 a b c

instance NFData Side where
    rnf LHS = ()
    rnf RHS = ()

instance NFData Goal where
    rnf (Goal a b) = rnf2 a b

newtype Proof a = Proof (ReaderT Known (StateT Unknown IO) a)
    deriving (Functor, Applicative, Monad, MonadIO, MonadThrow, MonadCatch, MonadMask)

getUnknown :: Proof (Known, Unknown)
getUnknown = Proof $ (,) <$> ask <*> lift get

getGoal :: Proof (Known, Unknown, Goal)
getGoal = do
    (known, unknown) <- getUnknown
    case goals unknown of
        [] -> fail "No goals left, proof is already complete"
        g:gs -> return (known, unknown, g)

unsafeReplaceFirstGoal :: [Goal] -> Proof ()
unsafeReplaceFirstGoal x = do
    liftIO $ evaluate $ rnf x
    Proof $ lift $ modify $ \s -> s{goals = x ++ drop 1 (goals s)}

setFocusSide :: Maybe Side -> Proof ()
setFocusSide x | () <- rnf x = Proof $ lift $ modify $ \s -> s{focusSide=x}

setFocusAt :: Int -> Proof ()
setFocusAt !x = Proof $ lift $ modify $ \s -> s{focusAt=x}


---------------------------------------------------------------------
-- BINDINGS

newtype Bind a = Bind (Writer [(Var,Exp)] a)
    deriving (Functor, Applicative, Monad)

addBind :: Var -> Exp -> Bind ()
addBind a b = Bind $ tell [(a,b)]

runBind :: Bind () -> [(Var,Exp)]
runBind (Bind x) = execWriter x
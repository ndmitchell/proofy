
module Classes(classes) where

import Proof.QED

classes = do
    lawsMonoid <- laws $ do
        law "a => a <> mempty = a"
        law "a => mempty <> a = a"
        law "a b c => a <> (b <> c) = (a <> b) <> c"

    lawsFunctor <- laws $ do
        law "fmap id = id"
        law "f g . fmap f . fmap g = fmap (f . g)"

    prove "x => [] ++ x = x" $ do
        unfold "++"

    prove "x => x ++ [] = x" $ do
        recurse
        rhs $ unfold "[]"

    prove "x y z => (x ++ y) ++ z = x ++ (y ++ z)" $ do
        recurse
        bhs $ unfold "++"

    satisfy lawsMonoid $ do
        bind "mempty = []"
        bind "(<>) = (++)"

    prove "map id = id" $ do
        bhs $ unfold "id"
        expand
        recurse
        rhs $ unfold "[]"

    prove "f g => map f . map g = map (f . g)" $ do
        unfold "."
        twice unlet
        rhs expand

    satisfy lawsFunctor $ do
        bind "fmap = map"
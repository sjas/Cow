module Cow.Substructure where

import           Control.Applicative    ((<$>), (<*>))

import           Data.Algorithm.Munkres (hungarianMethodDouble)
import           Data.Array.Unboxed
import           Data.Function          (on)
import           Data.List              (sortBy)
import           Data.Maybe             (fromJust, listToMaybe, mapMaybe)

import           Cow.Diff
import           Cow.Type

type Matching a = (AST a, AST a)

propagate :: (a -> b) -> Either a a -> Either b b
propagate fn (Left v) = Left $ fn v
propagate fn (Right v) = Right $ fn v

tagDiff :: Eq a => AST a -> AST a -> Diff a
tagDiff left right = foldr combine (diff left right) . zip [1..] $ matches
  where matches = sortBy (compare `on` weighMatching) $ match left right
        weighMatching (l, r) = subjectiveWeight $ diff l r
        combine (i, matching) oldTree = tagMatching i matching oldTree

tagMatching :: Eq a => Tag -> Matching a -> Diff a -> Diff a
tagMatching tagId (removed, added) diffTree
  | otherwise = either id id $ tagRemoved diffTree >>= tagAdded
  where toFrom (Del a) = (From tagId a)
        toFrom x = x
        toTo (Ins a) = (To tagId a)
        toTo x = x
        tagRemoved deleted@(Node (Del v) children)
          | (Del <$> removed) == deleted = Right . Node (From tagId v) $ map (toFrom <$>) children
        tagRemoved (Node v children) = propagate (Node v) $ combine children (tagRemoved <$> children)
        tagAdded inserted@(Node (Ins v) children)
          | (Ins <$> added) == inserted = Right . Node (To tagId v) $ map (toTo <$>) children
        tagAdded (Node v children) = propagate (Node v) $ combine children (tagAdded <$> children)
        combine children result = case foldl merge ([], False) $ zip children result of
            (newChildren, True)  -> Right newChildren
            (newChildren, False) -> Left newChildren
        merge (newChildren, found) (child, Right newChild)
          | found     = (newChildren ++ [child], True)
          | otherwise = (newChildren ++ [newChild], True)
        merge (newChildren, found) (child, Left{}) = (newChildren ++ [child], found)

match :: Eq a => AST a -> AST a -> [Matching a]
match left right = map toPair . fst $ hungarianMethodDouble inputArray
  where pairs = allPairs numLeft numRight
        numLeft  = number left
        numRight = number right
        lenLeft  = maximum $ map (fst . rootLabel . fst) pairs
        lenRight = maximum $ map (fst . rootLabel . snd) pairs
        getVal (l@(Node (li, _) _), r@(Node (ri, _) _)) =
          ((li, ri), weight (snd <$> l) (snd <$> r))
        inputArray = array ((1, 1), (lenLeft, lenRight)) $ getVal <$> pairs
        toPair (li, ri) = (fmap snd . fromJust $ findAST li numLeft,
                           fmap snd . fromJust $ findAST ri numRight)

findAST :: Eq i => i -> AST (i, a) -> Maybe (AST (i, a))
findAST i n@(Node (i', _) children)
  | i == i'    = Just n
  | otherwise = listToMaybe $ mapMaybe (findAST i) children

subjectiveWeight :: Eq a => Diff a -> Double
subjectiveWeight (Node Non{} children) = 1 + sum (subjectiveWeight <$> children)
subjectiveWeight (Node _ children)     = 0 + sum (subjectiveWeight <$> children)

weight :: Eq a => AST a -> AST a -> Double
weight a b = weighDiff 0.1 $ diff a b

number :: AST a -> AST (Int, a)
number = snd . go 1
  where go n (Node value [])       = (succ n, Node (n, value) [])
        go n (Node value children) = (n', Node (n, value) children')
          where (n', children') = foldl combine (succ n, []) children
                combine (i, acc) child =
                  let (i', child') = go i child in (i', acc ++ [child'])

allPairs :: AST (Int, a) -> AST (Int, a) -> [(AST (Int, a), AST (Int, a))]
allPairs l@(Node _ lChildren) r@(Node _ rChildren) = (l, r):(lefts ++ rights ++ rest)
  where lefts  = rChildren >>= allPairs l
        rights = lChildren >>= (`allPairs` r)
        rest   = concat $ allPairs <$> lChildren <*> rChildren


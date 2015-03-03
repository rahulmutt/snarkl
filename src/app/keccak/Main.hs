{-# LANGUAGE RebindableSyntax,DataKinds #-}

module Main where

import qualified Data.Map.Strict as Map
import Data.Bits hiding (xor)

import Prelude hiding 
  ( (>>)
  , (>>=)
  , (+)
  , (-)    
  , (*)    
  , (/)
  , (&&)        
  , not
  , return
  , fromRational
  , negate
  )
import qualified Prelude as P

import Syntax
import Source

index_of i j = (P.+) (((P.*) 5 i) `mod` 5) (j `mod` 5)

num_lanes :: Int
num_lanes = (P.*) 5 5

ln_width :: Int
ln_width = 1

round1 :: (Int -> TExp TBool Rational) -- | 'i'th bit of round constant
       -> TExp (TRef TBool) Rational   -- | Array 'a'
       -> Comp TUnit
round1 rc a
  = do { -- Allocate local array variables [b], [c], [d].
         b <- arr2 num_lanes ln_width
       ; c <- arr2 5 ln_width
       ; d <- arr2 5 ln_width
         -- Initialize arrays.
       ; forall_pairs ([0..24],[0..dec ln_width]) (\i j -> set2 (b,i,j) false)
       ; forall_pairs ([0..24],[0..dec ln_width]) (\i j -> set2 (c,i,j) false)
       ; forall_pairs ([0..24],[0..dec ln_width]) (\i j -> set2 (d,i,j) false) 
         -- \theta step         
       ; forall_pairs ([0..4],[0..dec ln_width]) (\x i ->
           do q <- get2 (a,index_of x 0,i)
              u <- get2 (a,index_of x 1,i)
              v <- get2 (a,index_of x 2,i)
              w <- get2 (a,index_of x 3,i)
              z <- get2 (a,index_of x 4,i)
              let e = q `xor` u `xor` v `xor` w `xor` z
              set2 (c,x,i) e)
       ; forall_pairs ([0..4],[0..dec ln_width]) (\x i ->
           do q <- get2 (a,dec x `mod` 5,i)
              u <- get2 (a,inc x `mod` 5,rot_index i 1)
              let e = q `xor` u
              set2 (d,x,i) e)
       ; forall_pairs ([0..4],[0..4]) (\x y ->
           forall [0..dec ln_width] (\i ->
             do q <- get2 (a,index_of x y,i)
                u <- get2 (d,x,i)
                set2 (a,index_of x y,i) (q `xor` u)))
         -- \rho and \pi steps         
       ; forall_pairs ([0..4],[0..4]) (\x y ->
           forall [0..dec ln_width] (\i ->     
             do q <- get2 (a,index_of x y,rot_index i (rot_tbl x y))
                set2 (b,index_of y ((P.+) ((P.*) 2 x) ((P.*) 3 y)),i) q))
         -- \chi step         
       ; forall_pairs ([0..4],[0..4]) (\x y ->
           forall [0..dec ln_width] (\i ->   
             do q <- get2 (b,index_of x y,i)
                u <- get2 (b,index_of (inc x) y,i)
                v <- get2 (b,index_of ((inc . inc) x) y,i)
                let e = q `xor` (not u && v)
                set2 (a,index_of x y,i) e))
         -- \iota step
       ; forall [0..dec ln_width] (\i ->
           do q <- get2 (a,index_of 0 0,i)
              set2 (a,index_of 0 0,i) (q `xor` rc i))
       }


-- round constants
round_consts :: [Integer]
round_consts
  = [ 0x00000001
    , 0x00008082
    , 0x0000808a
    , 0x80008000
    , 0x0000808b
    , 0x80000001
    , 0x80008081
    , 0x00008009
    , 0x0000008a
    , 0x00000088
    , 0x80008009
    , 0x8000000a

    , 0x8000808b
    , 0x800000000000008b
    , 0x8000000000008089
    , 0x8000000000008003
    , 0x8000000000008002
    , 0x8000000000000080
    , 0x800000000000800a
    , 0x800000008000000a
    , 0x8000000080008081
    , 0x8000000080008080
    , 0x0000000080000001
    , 0x8000000080008008                        
    ]

rot_index :: Int -- rotate index 'i'
          -> Int -- by 'n' (mod lane width)
          -> Int
rot_index i n = ((P.+) i n) `mod` ln_width

rot_tbl x y
  = let m = Map.fromList $
          [ ((3,2), 25), ((4,2), 39), ((0,2), 3),  ((1,2), 10), ((2,2), 43)
          , ((3,1), 55), ((4,1), 20), ((0,1), 36), ((1,1), 44), ((2,1), 6)
          , ((3,0), 28), ((4,0), 27), ((0,0), 0),  ((1,0), 1),  ((2,0), 62)
          , ((3,4), 56), ((4,4), 14), ((0,4), 18), ((1,4), 2),  ((2,4), 61)
          , ((3,3), 21), ((4,3), 8),  ((0,3), 41), ((1,3), 45), ((2,3), 15) ]
    in case Map.lookup (x,y) m of
         Nothing -> error $ show (x,y) ++ " not a valid rotation key"
         Just r -> r

trunc :: Integer -> Int
trunc rc
  = fromIntegral rc
    .&. dec (truncate (2**fromIntegral ln_width :: Double) :: Int)

get_round_bit :: Int -> Int -> TExp TBool Rational
get_round_bit round_i bit_i
  = let the_bit = round_consts !! round_i
                  .&. truncate (2**fromIntegral bit_i :: Double)
    in case the_bit > 0 of
         False -> false
         True -> true

keccak_f1 num_rounds a 
  = forall [0..dec num_rounds] (\round_i ->
      round1 (\bit_i -> get_round_bit round_i bit_i) a)

keccak1 num_rounds
  = do { a <- input_arr2 num_lanes ln_width
       ; keccak_f1 num_rounds a
       ; get (a,0)
       }

tests = [ ( keccak1 1
          , map fromIntegral
            $ take ((P.*) num_lanes ln_width)
            $ repeat (0::Int), 1
          )
        ]
  
main = mapM_ run_test tests

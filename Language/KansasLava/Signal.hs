{-# LANGUAGE FlexibleContexts, UndecidableInstances, TypeFamilies, FlexibleInstances, ScopedTypeVariables, MultiParamTypeClasses #-}

module Language.KansasLava.Signal where

import Language.KansasLava.Comb
import Language.KansasLava.Entity
import Language.KansasLava.Type
import Language.KansasLava.Wire
import Language.KansasLava.StdLogicVector
import Language.KansasLava.Entity.Utils
import Control.Applicative

import Data.Sized.Ix
import Data.Sized.Unsigned as U
import Data.Sized.Matrix as M

class Signal f where
  liftS0 :: Comb a -> f a
  liftS1 :: (Comb a -> Comb b) -> f a -> f b
  liftS2 :: (Comb a -> Comb b -> Comb c) -> f a -> f b -> f c
  liftSL :: ([Comb a] -> Comb b) -> [f a] -> f b

bitTypeOf :: forall f w . (Signal f, Wire w) => f w -> BaseTy
bitTypeOf _ = wireType (error "bitTypeOf" :: w)

op :: forall f w . (Signal f, Wire w) => f w -> String -> Name
op _ nm = Name (wireName (error "op" :: w)) nm

--class Constant a where
--  pureS :: (Signal s) => a -> s a

pureS :: (Signal s, RepWire a) => a -> s a
pureS a = liftS0 (toComb a)

-- An unknown (X) signal.
errorS :: (Signal s, RepWire a) => s a
errorS = liftS0 errorComb

-- | k is a constant

----------------------------------------------------------------------------------------------------

comment :: (Signal sig) => String -> sig a -> sig a
comment msg = liftS1 (\ (Comb s (D (Port v (E (Entity nm ins outs ann))))) 
		      -> Comb s (D (Port v (E (Entity nm ins outs (ann ++ [Comment msg]))))))

----------------------------------------------------------------------------------------------------

instance Signal Comb where
  liftS0 a     = a
  liftS1 f a   = f a
  liftS2 f a b = f a b
  liftSL f xs  = f xs


class (Signal sig) => Pack sig a where
 type Unpacked sig a
 pack :: Unpacked sig a -> sig a
 unpack :: sig a -> Unpacked sig a

--------------------------------------------------------------------------------

liftS3 :: forall a b c d sig . (Signal sig, Wire a, Wire b, Wire c, Wire d)
       => (Comb a -> Comb b -> Comb c -> Comb d) -> sig a -> sig b -> sig c -> sig d
liftS3 f a b c = liftS2 (\ ab c -> uncurry f (unpack ab) c) (pack (a,b) :: sig (a,b)) c

--------------------------------------------------------------------------------

fun0 :: forall a sig . (Signal sig, Wire a) => String -> a -> sig a
fun0 nm a = liftS0 $ Comb (optX $ Just $ a) $ entity0 (Name (wireName (error "fun1" :: a)) nm)

fun1 :: forall a b sig . (Signal sig, Wire a, Wire b) => String -> (a -> b) -> sig a -> sig b
fun1 nm f = liftS1 $ \ (Comb a ae) -> Comb (optX $ liftA f (unX a)) $ entity1 (Name (wireName (error "fun1" :: b)) nm) ae

fun2 :: forall a b c sig . (Signal sig, Wire a, Wire b, Wire c) => String -> (a -> b -> c) -> sig a -> sig b -> sig c
fun2 nm f = liftS2 $ \ (Comb a ae) (Comb b be) -> Comb (optX $ liftA2 f (unX a) (unX b))
	  $ entity2 (Name (wireName (error "fun2" :: c)) nm) ae be


-----------------------------------------------------------------------------------------------

instance (Wire a, Signal sig) => Pack sig (Maybe a) where
	type Unpacked sig (Maybe a) = (sig Bool, sig a)
	pack ~(a,b) = {-# SCC "pack(Maybe)" #-}
			liftS2 (\ ~(Comb a ae) ~(Comb b be) ->
				    Comb (case unX (a :: X Bool) :: Maybe Bool of
					    Nothing -> optX (Nothing :: Maybe (Maybe a))
					    Just False -> optX (Just Nothing :: Maybe (Maybe a))
					    Just True ->
						case unX (b :: X a) :: Maybe a of
						   Just v -> optX (Just (Just v) :: Maybe (Maybe a))
							-- This last one is strange.
						   Nothing -> optX (Just Nothing :: Maybe (Maybe a))
					 )
					 (entity2 (Name "Lava" "pair") ae be)
			     ) a b
	unpack ma = {-# SCC "unpack(Maybe)" #-}
		    ( liftS1 (\ (Comb a abe) -> Comb (case unX (a :: X (Maybe a)) :: Maybe (Maybe a) of
							Nothing -> optX (Nothing :: Maybe Bool)
							Just Nothing -> optX (Just False :: Maybe Bool)
							Just (Just _) -> optX (Just True :: Maybe Bool)
						     )
						     (entity1 (Name "Lava" "fst") abe)
			      ) ma
		    , liftS1 (\ (Comb a abe) -> Comb (case unX (a :: X (Maybe a)) :: Maybe (Maybe a) of
							Nothing -> optX (Nothing :: Maybe a)
							Just Nothing -> optX (Nothing :: Maybe a)
							Just (Just v) -> optX (Just v :: Maybe a)
						     )
						     (entity1 (Name "Lava" "snd") abe)
			      ) ma
		    )

instance (Wire a, Wire b, Signal sig) => Pack sig (a,b) where
	type Unpacked sig (a,b) = (sig a, sig b)
	pack ~(a,b) = {-# SCC "pack(,)" #-}
			liftS2 (\ ~(Comb a ae) ~(Comb b be) -> {-# SCC "pack(,)i" #-} Comb (a,b) (entity2 (Name "Lava" "pair") ae be))
			    a b
	unpack ab = {-# SCC "unpack(,)" #-}
		    ( liftS1 (\ (Comb (~(a,b)) abe) -> Comb a (entity1 (Name "Lava" "fst") abe)) ab
		    , liftS1 (\ (Comb (~(a,b)) abe) -> Comb b (entity1 (Name "Lava" "snd") abe)) ab
		    )

instance (Wire a, Wire b, Wire c, Signal sig) => Pack sig (a,b,c) where
	type Unpacked sig (a,b,c) = (sig a, sig b,sig c)
	pack ~(a,b,c) = liftS3 (\ ~(Comb a ae) ~(Comb b be) ~(Comb c ce) ->
				Comb (a,b,c)
				     (entity3 (Name "Lava" "triple") ae be ce))
			    a b c
	unpack abc = ( liftS1 (\ (Comb (~(a,b,c)) abce) -> Comb a (entity1 (Name "Lava" "fst3") abce)) abc
		    , liftS1 (\ (Comb (~(a,b,c)) abce) -> Comb b (entity1 (Name "Lava" "snd3") abce)) abc
		    , liftS1 (\ (Comb (~(a,b,c)) abce) -> Comb c (entity1 (Name "Lava" "thd3") abce)) abc
		    )



instance (Wire a, Signal sig, Size ix) => Pack sig (Matrix ix a) where
	type Unpacked sig (Matrix ix a) = Matrix ix (sig a)
	pack m = liftSL (\ ms -> let sh = M.fromList [ m | Comb m  _ <- ms ]
				     de = entityN (Name "Lava" "concat") [ d | Comb _ d <- ms ]
				 in Comb sh de) (M.toList m)
	unpack s = forAll $ \ ix ->
			liftS1 (\ (Comb s d) -> Comb (s ! ix)
					       (entity2 (Name "Lava" "index")
							(D $ Lit $ (mx ! ix) :: D Integer)
							d
					       )
			        ) s
	   where mx :: (Size ix) => Matrix ix Integer
		 mx = matrix (Prelude.zipWith (\ a b -> b) (M.indices mx) [0..])


instance (Size ix, Signal sig) => Pack sig (StdLogicVector ix) where
	type Unpacked sig (StdLogicVector ix) = Matrix ix (sig Bool)
	pack m = liftS1 matrixBool2slv (pack m)
	unpack sig = unpack (liftS1 slv2matrixBool sig)

-- TODO: find the 'lift/fmap' function inside here.
slv2matrixBool :: forall ix . (Size ix) => Comb (StdLogicVector ix) -> Comb (Matrix ix Bool)
slv2matrixBool (Comb s d) = Comb (case unX (s :: X (StdLogicVector ix)) of
		        Just (StdLogicVector m) -> optX (Just m)
	                Nothing -> optX (Nothing :: Maybe (Matrix ix Bool)))
		     (entity1 (Name "Lava" "id") d)

matrixBool2slv :: forall ix . (Size ix) => Comb (Matrix ix Bool) -> Comb (StdLogicVector ix)
matrixBool2slv (Comb s d) = Comb (case unX (s :: X (Matrix ix Bool)) of
		        Just  m -> optX (Just $ StdLogicVector m)
	                Nothing -> optX (Nothing :: Maybe (StdLogicVector ix)))
		     (entity1 (Name "Lava" "id") d)


> -- | These is the pretty printing functions, which produce SQL
> -- source from ASTs. The code attempts to format the output in a
> -- readable way.
> module Language.SQL.SimpleSQL.Pretty
>     (prettyQueryExpr
>     ,prettyValueExpr
>     ,prettyQueryExprs
>     ) where

TODO: there should be more comments in this file, especially the bits
which have been changed to try to improve the layout of the output.

> import Language.SQL.SimpleSQL.Syntax
> import Text.PrettyPrint (render, vcat, text, (<>), (<+>), empty, parens,
>                          nest, Doc, punctuate, comma, sep, quotes,
>                          doubleQuotes)
> import Data.Maybe (maybeToList, catMaybes)

> -- | Convert a query expr ast to concrete syntax.
> prettyQueryExpr :: QueryExpr -> String
> prettyQueryExpr = render . queryExpr

> -- | Convert a value expr ast to concrete syntax.
> prettyValueExpr :: ValueExpr -> String
> prettyValueExpr = render . valueExpr

> -- | Convert a list of query exprs to concrete syntax. A semi colon
> -- is inserted after each query expr.
> prettyQueryExprs :: [QueryExpr] -> String
> prettyQueryExprs = render . vcat . map ((<> text ";\n") . queryExpr)

= value expressions

> valueExpr :: ValueExpr -> Doc
> valueExpr (StringLit s) = quotes $ text $ doubleUpQuotes s
>   where doubleUpQuotes [] = []
>         doubleUpQuotes ('\'':cs) = '\'':'\'':doubleUpQuotes cs
>         doubleUpQuotes (c:cs) = c:doubleUpQuotes cs

> valueExpr (NumLit s) = text s
> valueExpr (IntervalLit v u p) =
>     text "interval" <+> quotes (text v)
>     <+> text u
>     <+> maybe empty (parens . text . show ) p
> valueExpr (Iden i) = name i
> valueExpr Star = text "*"
> valueExpr Parameter = text "?"

> valueExpr (App f es) = name f <> parens (commaSep (map valueExpr es))

> valueExpr (AggregateApp f d es od) =
>     name f
>     <> parens ((case d of
>                   Just Distinct -> text "distinct"
>                   Just All -> text "all"
>                   Nothing -> empty)
>                <+> commaSep (map valueExpr es)
>                <+> orderBy od)

> valueExpr (WindowApp f es pb od fr) =
>     name f <> parens (commaSep $ map valueExpr es)
>     <+> text "over"
>     <+> parens ((case pb of
>                     [] -> empty
>                     _ -> text "partition by"
>                           <+> nest 13 (commaSep $ map valueExpr pb))
>                 <+> orderBy od
>     <+> maybe empty frd fr)
>   where
>     frd (FrameFrom rs fp) = rsd rs <+> fpd fp
>     frd (FrameBetween rs fps fpe) =
>         rsd rs <+> text "between" <+> fpd fps
>         <+> text "and" <+> fpd fpe
>     rsd rs = case rs of
>                  FrameRows -> text "rows"
>                  FrameRange -> text "range"
>     fpd UnboundedPreceding = text "unbounded preceding"
>     fpd UnboundedFollowing = text "unbounded following"
>     fpd Current = text "current row"
>     fpd (Preceding e) = valueExpr e <+> text "preceding"
>     fpd (Following e) = valueExpr e <+> text "following"

> valueExpr (SpecialOp nm [a,b,c]) | nm `elem` [Name "between"
>                                               ,Name "not between"] =
>   sep [valueExpr a
>       ,name nm <+> valueExpr b
>       ,nest (length (unname nm) + 1) $ text "and" <+> valueExpr c]

> valueExpr (SpecialOp (Name "rowctor") as) =
>     parens $ commaSep $ map valueExpr as

> valueExpr (SpecialOp nm es) =
>   name nm <+> parens (commaSep $ map valueExpr es)

> valueExpr (SpecialOpK nm fs as) =
>     name nm <> parens (sep $ catMaybes
>         (fmap valueExpr fs
>          : map (\(n,e) -> Just (text n <+> valueExpr e)) as))

> valueExpr (PrefixOp f e) = name f <+> valueExpr e
> valueExpr (PostfixOp f e) = valueExpr e <+> name f
> valueExpr e@(BinOp _ op _) | op `elem` [Name "and", Name "or"] =
>     -- special case for and, or, get all the ands so we can vcat them
>     -- nicely
>     case ands e of
>       (e':es) -> vcat (valueExpr e'
>                        : map ((name op <+>) . valueExpr) es)
>       [] -> empty -- shouldn't be possible
>   where
>     ands (BinOp a op' b) | op == op' = ands a ++ ands b
>     ands x = [x]
> -- special case for . we don't use whitespace
> valueExpr (BinOp e0 (Name ".") e1) =
>     valueExpr e0 <> text "." <> valueExpr e1
> valueExpr (BinOp e0 f e1) =
>     valueExpr e0 <+> name f <+> valueExpr e1

> valueExpr (Case t ws els) =
>     sep $ [text "case" <+> maybe empty valueExpr t]
>           ++ map w ws
>           ++ maybeToList (fmap e els)
>           ++ [text "end"]
>   where
>     w (t0,t1) =
>       text "when" <+> nest 5 (commaSep $ map valueExpr t0)
>       <+> text "then" <+> nest 5 (valueExpr t1)
>     e el = text "else" <+> nest 5 (valueExpr el)
> valueExpr (Parens e) = parens $ valueExpr e
> valueExpr (Cast e tn) =
>     text "cast" <> parens (sep [valueExpr e
>                                ,text "as"
>                                ,typeName tn])

> valueExpr (TypedLit tn s) =
>     typeName tn <+> quotes (text s)

> valueExpr (SubQueryExpr ty qe) =
>     (case ty of
>         SqSq -> empty
>         SqExists -> text "exists"
>         SqAll -> text "all"
>         SqSome -> text "some"
>         SqAny -> text "any"
>     ) <+> parens (queryExpr qe)

> valueExpr (In b se x) =
>     valueExpr se <+>
>     (if b then empty else text "not")
>     <+> text "in"
>     <+> parens (nest (if b then 3 else 7) $
>                  case x of
>                      InList es -> commaSep $ map valueExpr es
>                      InQueryExpr qe -> queryExpr qe)

> unname :: Name -> String
> unname (QName n) = "\"" ++ n ++ "\""
> unname (Name n) = n

> name :: Name -> Doc
> name (QName n) = doubleQuotes $ text n
> name (Name n) = text n

> typeName :: TypeName -> Doc
> typeName (TypeName t) = text t
> typeName (PrecTypeName t a) = text t <+> parens (text $ show a)
> typeName (PrecScaleTypeName t a b) =
>     text t <+> parens (text (show a) <+> comma <+> text (show b))


= query expressions

> queryExpr :: QueryExpr -> Doc
> queryExpr (Select d sl fr wh gb hv od off fe) =
>   sep [text "select"
>       ,case d of
>           All -> empty
>           Distinct -> text "distinct"
>       ,nest 7 $ sep [selectList sl]
>       ,from fr
>       ,maybeValueExpr "where" wh
>       ,grpBy gb
>       ,maybeValueExpr "having" hv
>       ,orderBy od
>       ,maybe empty (\e -> text "offset" <+> valueExpr e <+> text "rows") off
>       ,maybe empty (\e -> text "fetch first" <+> valueExpr e
>                           <+> text "rows only") fe
>       ]
> queryExpr (CombineQueryExpr q1 ct d c q2) =
>   sep [queryExpr q1
>       ,text (case ct of
>                 Union -> "union"
>                 Intersect -> "intersect"
>                 Except -> "except")
>        <+> case d of
>                All -> empty
>                Distinct -> text "distinct"
>        <+> case c of
>                Corresponding -> text "corresponding"
>                Respectively -> empty
>       ,queryExpr q2]
> queryExpr (With rc withs qe) =
>   text "with" <+> (if rc then text "recursive" else empty)
>   <+> vcat [nest 5
>             (vcat $ punctuate comma $ flip map withs $ \(n,q) ->
>              alias n <+> text "as" <+> parens (queryExpr q))
>            ,queryExpr qe]
> queryExpr (Values vs) =
>     text "values"
>     <+> nest 7 (commaSep (map (parens . commaSep . map valueExpr) vs))
> queryExpr (Table t) = text "table" <+> name t


> alias :: Alias -> Doc
> alias (Alias nm cols) =
>     text "as" <+> name nm
>     <+> maybe empty (parens . commaSep . map name) cols

> selectList :: [(ValueExpr,Maybe Name)] -> Doc
> selectList is = commaSep $ map si is
>   where
>     si (e,al) = valueExpr e <+> maybe empty als al
>     als al = text "as" <+> name al

> from :: [TableRef] -> Doc
> from [] = empty
> from ts =
>     sep [text "from"
>         ,nest 5 $ vcat $ punctuate comma $ map tr ts]
>   where
>     tr (TRSimple t) = name t
>     tr (TRLateral t) = text "lateral" <+> tr t
>     tr (TRFunction f as) =
>         name f <> parens (commaSep $ map valueExpr as)
>     tr (TRAlias t a) = sep [tr t, alias a]
>     tr (TRParens t) = parens $ tr t
>     tr (TRQueryExpr q) = parens $ queryExpr q
>     tr (TRJoin t0 jt t1 jc) =
>        sep [tr t0
>            ,joinText jt jc <+> tr t1
>            ,joinCond jc]
>     joinText jt jc =
>       sep [case jc of
>               Just JoinNatural -> text "natural"
>               _ -> empty
>           ,case jt of
>               JInner -> text "inner"
>               JLeft -> text "left"
>               JRight -> text "right"
>               JFull -> text "full"
>               JCross -> text "cross"
>           ,text "join"]
>     joinCond (Just (JoinOn e)) = text "on" <+> valueExpr e
>     joinCond (Just (JoinUsing es)) =
>         text "using" <+> parens (commaSep $ map name es)
>     joinCond Nothing = empty
>     joinCond (Just JoinNatural) = empty

> maybeValueExpr :: String -> Maybe ValueExpr -> Doc
> maybeValueExpr k = maybe empty
>       (\e -> sep [text k
>                  ,nest (length k + 1) $ valueExpr e])

> grpBy :: [GroupingExpr] -> Doc
> grpBy [] = empty
> grpBy gs = sep [text "group by"
>                ,nest 9 $ commaSep $ map ge gs]
>   where
>     ge (SimpleGroup e) = valueExpr e
>     ge (GroupingParens g) = parens (commaSep $ map ge g)
>     ge (Cube es) = text "cube" <> parens (commaSep $ map ge es)
>     ge (Rollup es) = text "rollup" <> parens (commaSep $ map ge es)
>     ge (GroupingSets es) = text "grouping sets" <> parens (commaSep $ map ge es)

> orderBy :: [SortSpec] -> Doc
> orderBy [] = empty
> orderBy os = sep [text "order by"
>                  ,nest 9 $ commaSep $ map f os]
>   where
>     f (SortSpec e d n) =
>         valueExpr e
>         <+> (if d == Asc then empty else text "desc")
>         <+> (case n of
>                 NullsOrderDefault -> empty
>                 NullsFirst -> text "nulls" <+> text "first"
>                 NullsLast -> text "nulls" <+> text "last")

= utils

> commaSep :: [Doc] -> Doc
> commaSep ds = sep $ punctuate comma ds

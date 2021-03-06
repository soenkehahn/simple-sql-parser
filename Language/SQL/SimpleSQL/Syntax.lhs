
> -- | The AST for SQL queries.
> module Language.SQL.SimpleSQL.Syntax
>     (-- * Value expressions
>      ValueExpr(..)
>     ,Name(..)
>     ,TypeName(..)
>     ,SetQuantifier(..)
>     ,SortSpec(..)
>     ,Direction(..)
>     ,NullsOrder(..)
>     ,InPredValue(..)
>     ,SubQueryExprType(..)
>     ,Frame(..)
>     ,FrameRows(..)
>     ,FramePos(..)
>      -- * Query expressions
>     ,QueryExpr(..)
>     ,makeSelect
>     ,CombineOp(..)
>     ,Corresponding(..)
>     ,Alias(..)
>     ,GroupingExpr(..)
>      -- ** From
>     ,TableRef(..)
>     ,JoinType(..)
>     ,JoinCondition(..)
>     ) where


> -- | Represents a value expression. This is used for the expressions
> -- in select lists. It is also used for expressions in where, group
> -- by, having, order by and so on.
> data ValueExpr
>     = -- | a numeric literal optional decimal point, e+-
>       -- integral exponent, e.g
>       --
>       -- * 10
>       --
>       -- * 10.
>       --
>       -- * .1
>       --
>       -- * 10.1
>       --
>       -- * 1e5
>       --
>       -- * 12.34e-6
>       NumLit String
>       -- | string literal, currently only basic strings between
>       -- single quotes with a single quote escaped using ''
>     | StringLit String
>       -- | text of interval literal, units of interval precision,
>       -- e.g. interval 3 days (3)
>     | IntervalLit
>       {ilLiteral :: String -- ^ literal text
>       ,ilUnits :: String -- ^ units
>       ,ilPrecision :: Maybe Int -- ^ precision
>       }
>       -- | identifier without dots
>     | Iden Name
>       -- | star, as in select *, t.*, count(*)
>     | Star
>       -- | function application (anything that looks like c style
>       -- function application syntactically)
>     | App Name [ValueExpr]
>       -- | aggregate application, which adds distinct or all, and
>       -- order by, to regular function application
>     | AggregateApp
>       {aggName :: Name -- ^ aggregate function name
>       ,aggDistinct :: Maybe SetQuantifier -- ^ distinct
>       ,aggArgs :: [ValueExpr]-- ^ args
>       ,aggOrderBy :: [SortSpec] -- ^ order by
>       }
>       -- | window application, which adds over (partition by a order
>       -- by b) to regular function application. Explicit frames are
>       -- not currently supported
>     | WindowApp
>       {wnName :: Name -- ^ window function name
>       ,wnArgs :: [ValueExpr] -- ^ args
>       ,wnPartition :: [ValueExpr] -- ^ partition by
>       ,wnOrderBy :: [SortSpec] -- ^ order by
>       ,wnFrame :: Maybe Frame -- ^ frame clause
>       }
>       -- | Infix binary operators. This is used for symbol operators
>       -- (a + b), keyword operators (a and b) and multiple keyword
>       -- operators (a is similar to b)
>     | BinOp ValueExpr Name ValueExpr
>       -- | Prefix unary operators. This is used for symbol
>       -- operators, keyword operators and multiple keyword operators.
>     | PrefixOp Name ValueExpr
>       -- | Postfix unary operators. This is used for symbol
>       -- operators, keyword operators and multiple keyword operators.
>     | PostfixOp Name ValueExpr
>       -- | Used for ternary, mixfix and other non orthodox
>       -- operators. Currently used for row constructors, and for
>       -- between.
>     | SpecialOp Name [ValueExpr]
>       -- | Used for the operators which look like functions
>       -- except the arguments are separated by keywords instead
>       -- of commas. The maybe is for the first unnamed argument
>       -- if it is present, and the list is for the keyword argument
>       -- pairs.
>     | SpecialOpK Name (Maybe ValueExpr) [(String,ValueExpr)]
>       -- | case expression. both flavours supported
>     | Case
>       {caseTest :: Maybe ValueExpr -- ^ test value
>       ,caseWhens :: [([ValueExpr],ValueExpr)] -- ^ when branches
>       ,caseElse :: Maybe ValueExpr -- ^ else value
>       }
>     | Parens ValueExpr
>       -- | cast(a as typename)
>     | Cast ValueExpr TypeName
>       -- | prefix 'typed literal', e.g. int '42'
>     | TypedLit TypeName String
>       -- | exists, all, any, some subqueries
>     | SubQueryExpr SubQueryExprType QueryExpr
>       -- | in list literal and in subquery, if the bool is false it
>       -- means not in was used ('a not in (1,2)')
>     | In Bool ValueExpr InPredValue
>     | Parameter -- ^ Represents a ? in a parameterized query
>       deriving (Eq,Show,Read)

> -- | Represents an identifier name, which can be quoted or unquoted.
> data Name = Name String
>           | QName String
>             deriving (Eq,Show,Read)

> -- | Represents a type name, used in casts.
> data TypeName = TypeName String
>               | PrecTypeName String Int
>               | PrecScaleTypeName String Int Int
>                 deriving (Eq,Show,Read)


> -- | Used for 'expr in (value expression list)', and 'expr in
> -- (subquery)' syntax.
> data InPredValue = InList [ValueExpr]
>                  | InQueryExpr QueryExpr
>                    deriving (Eq,Show,Read)

> -- | A subquery in a value expression.
> data SubQueryExprType
>     = -- | exists (query expr)
>       SqExists
>       -- | a scalar subquery
>     | SqSq
>       -- | all (query expr)
>     | SqAll
>       -- | some (query expr)
>     | SqSome
>       -- | any (query expr)
>     | SqAny
>       deriving (Eq,Show,Read)

> -- | Represents one field in an order by list.
> data SortSpec = SortSpec ValueExpr Direction NullsOrder
>                 deriving (Eq,Show,Read)

> -- | Represents 'nulls first' or 'nulls last' in an order by clause.
> data NullsOrder = NullsOrderDefault
>                 | NullsFirst
>                 | NullsLast
>                   deriving (Eq,Show,Read)

> -- | Represents the frame clause of a window
> -- this can be [range | rows] frame_start
> -- or [range | rows] between frame_start and frame_end
> data Frame = FrameFrom FrameRows FramePos
>            | FrameBetween FrameRows FramePos FramePos
>              deriving (Eq,Show,Read)

> -- | Represents whether a window frame clause is over rows or ranges.
> data FrameRows = FrameRows | FrameRange
>                  deriving (Eq,Show,Read)

> -- | represents the start or end of a frame
> data FramePos = UnboundedPreceding
>               | Preceding ValueExpr
>               | Current
>               | Following ValueExpr
>               | UnboundedFollowing
>                 deriving (Eq,Show,Read)

> -- | Represents a query expression, which can be:
> --
> -- * a regular select;
> --
> -- * a set operator (union, except, intersect);
> --
> -- * a common table expression (with);
> --
> -- * a table value constructor (values (1,2),(3,4)); or
> --
> -- * an explicit table (table t).
> data QueryExpr
>     = Select
>       {qeSetQuantifier :: SetQuantifier
>       ,qeSelectList :: [(ValueExpr,Maybe Name)]
>        -- ^ the expressions and the column aliases

TODO: consider breaking this up. The SQL grammar has
queryexpr = select <select list> [<table expression>]
table expression = <from> [where] [groupby] [having] ...

This would make some things a bit cleaner?

>       ,qeFrom :: [TableRef]
>       ,qeWhere :: Maybe ValueExpr
>       ,qeGroupBy :: [GroupingExpr]
>       ,qeHaving :: Maybe ValueExpr
>       ,qeOrderBy :: [SortSpec]
>       ,qeOffset :: Maybe ValueExpr
>       ,qeFetchFirst :: Maybe ValueExpr
>       }
>     | CombineQueryExpr
>       {qe0 :: QueryExpr
>       ,qeCombOp :: CombineOp
>       ,qeSetQuantifier :: SetQuantifier
>       ,qeCorresponding :: Corresponding
>       ,qe1 :: QueryExpr
>       }
>     | With
>       {qeWithRecursive :: Bool
>       ,qeViews :: [(Alias,QueryExpr)]
>       ,qeQueryExpression :: QueryExpr}
>     | Values [[ValueExpr]]
>     | Table Name
>       deriving (Eq,Show,Read)

TODO: add queryexpr parens to deal with e.g.
(select 1 union select 2) union select 3
I'm not sure if this is valid syntax or not.

> -- | Helper/'default' value for query exprs to make creating query
> -- expr values a little easier. It is defined like this:
> --
> -- > makeSelect :: QueryExpr
> -- > makeSelect = Select {qeSetQuantifier = All
> -- >                     ,qeSelectList = []
> -- >                     ,qeFrom = []
> -- >                     ,qeWhere = Nothing
> -- >                     ,qeGroupBy = []
> -- >                     ,qeHaving = Nothing
> -- >                     ,qeOrderBy = []
> -- >                     ,qeOffset = Nothing
> -- >                     ,qeFetchFirst = Nothing}

> makeSelect :: QueryExpr
> makeSelect = Select {qeSetQuantifier = All
>                     ,qeSelectList = []
>                     ,qeFrom = []
>                     ,qeWhere = Nothing
>                     ,qeGroupBy = []
>                     ,qeHaving = Nothing
>                     ,qeOrderBy = []
>                     ,qeOffset = Nothing
>                     ,qeFetchFirst = Nothing}


> -- | Represents the Distinct or All keywords, which can be used
> -- before a select list, in an aggregate/window function
> -- application, or in a query expression set operator.
> data SetQuantifier = Distinct | All deriving (Eq,Show,Read)

> -- | The direction for a column in order by.
> data Direction = Asc | Desc deriving (Eq,Show,Read)
> -- | Query expression set operators.
> data CombineOp = Union | Except | Intersect deriving (Eq,Show,Read)
> -- | Corresponding, an option for the set operators.
> data Corresponding = Corresponding | Respectively deriving (Eq,Show,Read)

> -- | Represents an item in a group by clause.
> data GroupingExpr
>     = GroupingParens [GroupingExpr]
>     | Cube [GroupingExpr]
>     | Rollup [GroupingExpr]
>     | GroupingSets [GroupingExpr]
>     | SimpleGroup ValueExpr
>       deriving (Eq,Show,Read)

> -- | Represents a entry in the csv of tables in the from clause.
> data TableRef = -- | from t
>                 TRSimple Name
>                 -- | from a join b
>               | TRJoin TableRef JoinType TableRef (Maybe JoinCondition)
>                 -- | from (a)
>               | TRParens TableRef
>                 -- | from a as b(c,d)
>               | TRAlias TableRef Alias
>                 -- | from (query expr)
>               | TRQueryExpr QueryExpr
>                 -- | from function(args)
>               | TRFunction Name [ValueExpr]
>                 -- | from lateral t
>               | TRLateral TableRef
>                 deriving (Eq,Show,Read)

> -- | Represents an alias for a table valued expression, used in with
> -- queries and in from alias, e.g. select a from t u, select a from t u(b),
> -- with a(c) as select 1, select * from a.
> data Alias = Alias Name (Maybe [Name])
>              deriving (Eq,Show,Read)

> -- | The type of a join.
> data JoinType = JInner | JLeft | JRight | JFull | JCross
>                 deriving (Eq,Show,Read)

> -- | The join condition.
> data JoinCondition = JoinOn ValueExpr -- ^ on expr
>                    | JoinUsing [Name] -- ^ using (column list)
>                    | JoinNatural -- ^ natural join was used
>                      deriving (Eq,Show,Read)

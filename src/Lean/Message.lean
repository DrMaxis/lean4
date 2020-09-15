/-
Copyright (c) 2018 Microsoft Corporation. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Author: Sebastian Ullrich, Leonardo de Moura

Message Type used by the Lean frontend
-/
import Lean.Data.Position
import Lean.Syntax
import Lean.MetavarContext
import Lean.Environment
import Lean.Util.PPExt
import Lean.Util.PPGoal

namespace Lean
def mkErrorStringWithPos (fileName : String) (line col : Nat) (msg : String) : String :=
fileName ++ ":" ++ toString line ++ ":" ++ toString col ++ " " ++ toString msg

inductive MessageSeverity
| information | warning | error

structure MessageDataContext :=
(env : Environment) (mctx : MetavarContext) (lctx : LocalContext) (opts : Options)

/- Structure message data. We use it for reporting errors, trace messages, etc. -/
inductive MessageData
| ofFormat    : Format → MessageData
| ofSyntax    : Syntax → MessageData
| ofExpr      : Expr → MessageData
| ofLevel     : Level → MessageData
| ofName      : Name  → MessageData
| ofGoal      : MVarId → MessageData
/- `withContext ctx d` specifies the pretty printing context `(env, mctx, lctx, opts)` for the nested expressions in `d`. -/
| withContext : MessageDataContext → MessageData → MessageData
/- Lifted `Format.nest` -/
| nest        : Nat → MessageData → MessageData
/- Lifted `Format.group` -/
| group       : MessageData → MessageData
/- Lifted `Format.compose` -/
| compose     : MessageData → MessageData → MessageData
/- Tagged sections. `Name` should be viewed as a "kind", and is used by `MessageData` inspector functions.
   Example: an inspector that tries to find "definitional equality failures" may look for the tag "DefEqFailure". -/
| tagged      : Name → MessageData → MessageData
| node        : Array MessageData → MessageData

namespace MessageData

instance : Inhabited MessageData := ⟨MessageData.ofFormat (arbitrary _)⟩

@[init] def stxMaxDepthOption : IO Unit :=
registerOption `syntaxMaxDepth { defValue := (2 : Nat), group := "", descr := "maximum depth when displaying syntax objects in messages" }

def getSyntaxMaxDepth (opts : Options) : Nat :=
opts.getNat `syntaxMaxDepth 2

def sanitizeNamesDefault := true
@[init] def sanitizeNamesOption : IO Unit :=
registerOption `pp.sanitizeNames { defValue := sanitizeNamesDefault, group := "pp", descr := "add suffix '_{<idx>}' to shadowed variables when pretty printing" }
def getSanitizeNames (o : Options) : Bool:= o.get `pp.sanitizeNames sanitizeNamesDefault

private def sanitizeNames (ctx : MessageDataContext) : MessageDataContext :=
if getSanitizeNames ctx.opts then
  { ctx with lctx := ctx.lctx.sanitizeNames }
else
  ctx

partial def formatAux : Option MessageDataContext → MessageData → Format
| _,         ofFormat fmt      => fmt
| _,         ofLevel u         => fmt u
| _,         ofName n          => fmt n
| some ctx,  ofSyntax s        => s.formatStx (getSyntaxMaxDepth ctx.opts)
| none,      ofSyntax s        => s.formatStx
| none,      ofExpr e          => format (toString e)
| some ctx,  ofExpr e          => ppExpr ctx.env ctx.mctx ctx.lctx ctx.opts e
| none,      ofGoal mvarId     => "goal " ++ format (mkMVar mvarId)
| some ctx,  ofGoal mvarId     => ppGoal ctx.env ctx.mctx ctx.opts mvarId
| _,         withContext ctx d => formatAux (some $ sanitizeNames ctx) d
| ctx,       tagged cls d      => Format.sbracket (format cls) ++ " " ++ formatAux ctx d
| ctx,       nest n d          => Format.nest n (formatAux ctx d)
| ctx,       compose d₁ d₂     => formatAux ctx d₁ ++ formatAux ctx d₂
| ctx,       group d           => Format.group (formatAux ctx d)
| ctx,       node ds           => Format.nest 2 $ ds.foldl (fun r d => r ++ Format.line ++ formatAux ctx d) Format.nil

protected def format (msgData : MessageData) : Format :=
formatAux none msgData

instance : HasAppend MessageData := ⟨compose⟩
instance : HasFormat MessageData := ⟨fun d => MessageData.format d⟩
instance : HasToString MessageData := ⟨fun d => toString (format d)⟩

instance hasCoeOfFormat    : HasCoe Format MessageData := ⟨ofFormat⟩
instance hasCoeOfLevel     : HasCoe Level MessageData  := ⟨ofLevel⟩
instance hasCoeOfExpr      : HasCoe Expr MessageData   := ⟨ofExpr⟩
instance hasCoeOfName      : HasCoe Name MessageData   := ⟨ofName⟩
instance hasCoeOfSyntax    : HasCoe Syntax MessageData := ⟨ofSyntax⟩
instance hasCoeOfOptExpr   : HasCoe (Option Expr) MessageData :=
⟨fun o => match o with | none => "none" | some e => ofExpr e⟩

instance coeOfString    : Coe String MessageData := ⟨ofFormat ∘ format⟩
instance coeOfFormat    : Coe Format MessageData := ⟨ofFormat⟩
instance coeOfLevel     : Coe Level MessageData  := ⟨ofLevel⟩
instance coeOfExpr      : Coe Expr MessageData   := ⟨ofExpr⟩
instance coeOfName      : Coe Name MessageData   := ⟨ofName⟩
instance coeOfSyntax    : Coe Syntax MessageData := ⟨ofSyntax⟩
instance coeOfOptExpr   : Coe (Option Expr) MessageData :=
⟨fun o => match o with | none => "none" | some e => ofExpr e⟩

partial def arrayExpr.toMessageData (es : Array Expr) : Nat → MessageData → MessageData
| i, acc =>
  if h : i < es.size then
    let e   := es.get ⟨i, h⟩;
    let acc := if i == 0 then acc ++ ofExpr e else acc ++ ", " ++ ofExpr e;
    arrayExpr.toMessageData (i+1) acc
  else
    acc ++ "]"

instance hasCoeOfArrayExpr : HasCoe (Array Expr) MessageData := ⟨fun es => arrayExpr.toMessageData es 0 "#["⟩

instance coeOfArrayExpr : Coe (Array Expr) MessageData := ⟨fun es => arrayExpr.toMessageData es 0 "#["⟩

def bracket (l : String) (f : MessageData) (r : String) : MessageData := group (nest l.length $ l ++ f ++ r)
def paren (f : MessageData) : MessageData := bracket "(" f ")"
def sbracket (f : MessageData) : MessageData := bracket "[" f "]"
def joinSep : List MessageData → MessageData → MessageData
| [],    sep => Format.nil
| [a],   sep => a
| a::as, sep => a ++ sep ++ joinSep as sep
def ofList: List MessageData → MessageData
| [] => "[]"
| xs => sbracket $ joinSep xs ("," ++ Format.line)
def ofArray (msgs : Array MessageData) : MessageData :=
ofList msgs.toList

instance hasCoeOfList     : HasCoe (List MessageData) MessageData := ⟨ofList⟩
instance hasCoeOfListExpr : HasCoe (List Expr) MessageData := ⟨fun es => ofList $ es.map ofExpr⟩

instance coeOfList     : Coe (List MessageData) MessageData := ⟨ofList⟩
instance coeOfListExpr : Coe (List Expr) MessageData := ⟨fun es => ofList $ es.map ofExpr⟩

end MessageData

structure Message :=
(fileName : String)
(pos      : Position)
(endPos   : Option Position := none)
(severity : MessageSeverity := MessageSeverity.error)
(caption  : String          := "")
(data     : MessageData)

@[export lean_mk_message]
def mkMessageEx (fileName : String) (pos : Position) (endPos : Option Position) (severity : MessageSeverity) (caption : String) (text : String) : Message :=
{ fileName := fileName, pos := pos, endPos := endPos, severity := severity, caption := caption, data := text }
namespace Message

protected def toString (msg : Message) : String :=
mkErrorStringWithPos msg.fileName msg.pos.line msg.pos.column
 ((match msg.severity with
   | MessageSeverity.information => ""
   | MessageSeverity.warning => "warning: "
   | MessageSeverity.error => "error: ") ++
  (if msg.caption == "" then "" else msg.caption ++ ":\n") ++ toString (fmt msg.data))

instance : Inhabited Message :=
⟨{ fileName := "", pos := ⟨0, 1⟩, data := arbitrary _}⟩

instance : HasToString Message :=
⟨Message.toString⟩

@[export lean_message_pos] def getPostEx (msg : Message) : Position := msg.pos
@[export lean_message_severity] def getSeverityEx (msg : Message) : MessageSeverity := msg.severity
@[export lean_message_string] def getMessageStringEx (msg : Message) : String := toString (fmt msg.data)

end Message

structure MessageLog :=
(msgs : Std.PersistentArray Message := {})

namespace MessageLog
def empty : MessageLog := ⟨{}⟩

def isEmpty (log : MessageLog) : Bool :=
log.msgs.isEmpty

instance : Inhabited MessageLog := ⟨{}⟩

def add (msg : Message) (log : MessageLog) : MessageLog :=
⟨log.msgs.push msg⟩

protected def append (l₁ l₂ : MessageLog) : MessageLog :=
⟨l₁.msgs ++ l₂.msgs⟩

instance : HasAppend MessageLog :=
⟨MessageLog.append⟩

def hasErrors (log : MessageLog) : Bool :=
log.msgs.any $ fun m => match m.severity with
| MessageSeverity.error => true
| _                     => false

def errorsToWarnings (log : MessageLog) : MessageLog :=
{ msgs := log.msgs.map (fun m => match m.severity with | MessageSeverity.error => { m with severity := MessageSeverity.warning } | _ => m) }

def forM {m : Type → Type} [Monad m] (log : MessageLog) (f : Message → m Unit) : m Unit :=
log.msgs.forM f

def toList (log : MessageLog) : List Message :=
(log.msgs.foldl (fun acc msg => msg :: acc) []).reverse

end MessageLog

def MessageData.nestD (msg : MessageData) : MessageData :=
MessageData.nest 2 msg

def indentD (msg : MessageData) : MessageData :=
MessageData.nestD (Format.line ++ msg)

def indentExpr (e : Expr) : MessageData :=
indentD e

namespace KernelException

private def mkCtx (env : Environment) (lctx : LocalContext) (opts : Options) (msg : MessageData) : MessageData :=
MessageData.withContext { env := env, mctx := {}, lctx := lctx, opts := opts } msg

def toMessageData (e : KernelException) (opts : Options) : MessageData :=
match e with
| unknownConstant env constName       => mkCtx env {} opts $ "(kernel) unknown constant " ++ constName
| alreadyDeclared env constName       => mkCtx env {} opts $ "(kernel) constant has already been declared " ++ constName
| declTypeMismatch env decl givenType =>
  let process (n : Name) (expectedType : Expr) : MessageData :=
    "(kernel) declaration type mismatch " ++ n
    ++ Format.line ++ "has type" ++ indentExpr givenType
    ++ Format.line ++ "but it is expected to have type" ++ indentExpr expectedType;
  match decl with
  | Declaration.defnDecl { name := n, type := type, .. } => process n type
  | Declaration.thmDecl { name := n, type := type, .. }  => process n type
  | _ => "(kernel) declaration type mismatch" -- TODO fix type checker, type mismatch for mutual decls does not have enough information
| declHasMVars env constName _        => mkCtx env {} opts $ "(kernel) declaration has metavariables " ++ constName
| declHasFVars env constName _        => mkCtx env {} opts $ "(kernel) declaration has free variables " ++ constName
| funExpected env lctx e              => mkCtx env lctx opts $ "(kernel) function expected" ++ indentExpr e
| typeExpected env lctx e             => mkCtx env lctx opts $ "(kernel) type expected" ++ indentExpr e
| letTypeMismatch  env lctx n _ _     => mkCtx env lctx opts $ "(kernel) let-declaration type mismatch " ++ n
| exprTypeMismatch env lctx e _       => mkCtx env lctx opts $ "(kernel) type mismatch at " ++ indentExpr e
| appTypeMismatch  env lctx e fnType argType =>
  mkCtx env lctx opts $
    "application type mismatch" ++ indentExpr e
    ++ Format.line ++ "argument has type" ++ indentExpr argType
    ++ Format.line ++ "but function has type" ++ indentExpr fnType
| invalidProj env lctx e              => mkCtx env lctx opts $ "(kernel) invalid projection" ++ indentExpr e
| other msg                           => "(kernel) " ++ msg

end KernelException

class AddMessageDataContext (m : Type → Type) :=
(addMessageDataContext : MessageData → m MessageData)

export AddMessageDataContext (addMessageDataContext)

instance addMessageDataContextTrans (m n) [AddMessageDataContext m] [MonadLift m n] : AddMessageDataContext n :=
{ addMessageDataContext := fun msg => liftM (addMessageDataContext msg : m _) }

def addMessageDataContextPartial {m} [Monad m] [MonadEnv m] [MonadOptions m] (msgData : MessageData) : m MessageData := do
env ← getEnv;
opts ← getOptions;
pure $ MessageData.withContext { env := env, mctx := {}, lctx := {}, opts := opts } msgData

def addMessageDataContextFull {m} [Monad m] [MonadEnv m] [MonadMCtx m] [MonadLCtx m] [MonadOptions m] (msgData : MessageData) : m MessageData := do
env ← getEnv;
mctx ← getMCtx;
lctx ← getLCtx;
opts ← getOptions;
pure $ MessageData.withContext { env := env, mctx := mctx, lctx := lctx, opts := opts } msgData

end Lean

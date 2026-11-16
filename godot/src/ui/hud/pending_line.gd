class_name PendingLine extends RefCounted
## "Order from Aino: escort Bomber 2 (on release)": the order a teammate or the Commander left on a unit the local
## player now pilots (docs/06 s6.1, UX-19; reads SimView.pending_order, shown on events).

var entity: int = 0
var kind: int = 0
var issuer: int = -1
var issuer_name: String = ""
var target: int = 0
var target_label: String = ""


## Null when `id` has no pending order. `target_label` is Callable(id: int) -> String (may be empty: a generic word is used).
static func from_view(v: SimView, id: int, names: Dictionary, label: Callable) -> PendingLine:
	var o: OrderSpec = v.pending_order(id)
	if o == null:
		return null
	var p: PendingLine = PendingLine.new()
	p.entity = id
	p.kind = o.kind
	p.issuer = o.issuer
	p.issuer_name = PilotedBadges.name_of(o.issuer, names) if o.issuer >= 0 else TranslationServer.translate(&"hud.pending.system")
	p.target = o.target
	p.target_label = TranslationServer.translate(&"hud.pending.target")
	if o.target != 0 and label.is_valid():
		p.target_label = str(label.call(o.target))
	return p


static func verb_key(k: int) -> StringName:
	return StringName("hud.pending.verb.%s" % OrderSpec.KIND_NAMES[clampi(k, 0, OrderSpec.KIND_NAMES.size() - 1)])


func text() -> String:
	var verb: String = tr(verb_key(kind)).format({"target": target_label})
	return tr(&"hud.pending.line").format({"name": issuer_name, "order": verb})

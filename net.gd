# Naval IO - tiny networking helpers for HOST MATCH / JOIN MATCH over the plain internet.
#
# HOW IT WORKS (honest version):
#  - The HOST opens an ENet UDP port (7070) inside the game.
#  - With UPnP the host's game asks the home router to forward that port automatically.
#  - A friend types the host's public internet address (shown on the host's screen)
#    and connects straight to it. No VPN, no rented server, no accounts.
#  - Routers with UPnP turned off can't be opened from inside - the game says so and
#    the host can enable UPnP in router settings or port-forward 7070/UDP by hand.
#
# Both players MUST run the same version of this game (same data.gd), because the
# host and the friend build the world from the same seed.

const PORT := 7070

# client -> host
const M_HELLO := 10   # [nick, paint_kind]
const M_INPUT := 12   # [up, down, left, right, cursor, fire, ctrl_air, wsel]
const M_ABILITY := 13 # [ability_idx]
const M_PICK := 15    # [def_id]  (respawn or promotion pick)

# host -> client
const M_WORLD := 11   # [world_seed, your_ship_idx, your_peer_id]
const M_SNAP := 20    # [your_ship_idx, [ship entries...]]
const M_SHOTS := 21   # [[weapon_id, origin, ang, tgt, vel, src_idx]...]
const M_FX := 22      # [[kind, pos, size, dur, color, ang]...]
const M_ECON := 23    # [for_peer, xp, rp, bp, kills, dmg]  (battle progress)
const M_DIED := 24    # [victim_idx, killer_name, score, from_tier, to_tier, progress, rp_penalty]
const M_FEED := 25    # [text]
const M_PROMO := 26   # [ship_idx, to_tier]
const M_CRATES := 27  # [[pos, kind, phase]...]

static func setup_upnp() -> Array:
	# returns [ok, external_ip, fail_reason]
	var out := [false, "", ""]
	if not ClassDB.class_exists("UPnP"):
		out[2] = "no UPnP in this build"
		return out
	var u = null
	if ClassDB.can_instantiate("UPnP"):
		u = ClassDB.instantiate("UPnP")
	if u == null or not u.has_method("discover"):
		out[2] = "no UPnP in this build"
		return out
	u.discover()
	var gw = null
	if u.has_method("get_gateway"):
		gw = u.get_gateway()
	if gw == null:
		out[2] = "router has no UPnP"
		return out
	gw.add_port_mapping(PORT, PORT, "naval_io", "UDP")
	var ip := ""
	if u.has_method("query_external_address"):
		ip = str(u.query_external_address())
	if ip == "":
		out[2] = "router refused the mapping"
		return out
	out[0] = true
	out[1] = ip
	return out

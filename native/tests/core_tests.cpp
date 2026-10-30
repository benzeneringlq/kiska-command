#include "tactical_core.hpp"
#include <cstdlib>
#include <iostream>
using namespace ridgeline;
static void check(bool value, const char *label) {
    if (!value) { std::cerr << "FAILED: " << label << '\n'; std::exit(1); }
}
int main() {
    Weapon w;
    check(w.fire() && w.rounds == 29, "shot consumes ammunition");
    check(!w.fire(), "fire rate is bounded");
    w.advance(0.11);
    check(w.reload() && !w.fire(), "reload blocks firing");
    w.advance(2.34);
    check(w.rounds == 29, "reload does not complete early");
    w.advance(0.02);
    check(w.rounds == 30 && w.reserve == 179, "reload conserves ammunition");
    w.rounds = 27; w.reserve = 1;
    check(w.reload(), "partial reload starts"); w.advance(3);
    check(w.rounds == 28 && w.reserve == 0, "partial reload respects reserve");
    check(!w.reload(), "empty reserve cannot reload");
    Weapon belt;
    belt.capacity = 100; belt.rounds = 100; belt.fire_interval = 0.06; belt.reload_duration = 5.0;
    check(belt.fire(), "configurable belt-fed weapon fires"); belt.advance(0.061);
    check(belt.fire() && belt.rounds == 98, "weapon-specific fire interval");
    check(belt.reload(), "belt reload starts"); belt.advance(2.4);
    check(belt.rounds == 98, "long reload does not use rifle timing"); belt.advance(2.7);
    check(belt.rounds == 100 && belt.reserve == 178, "configurable capacity preserves ammunition");
    SoldierMind m;
    m.advance(1,true,20,false);
    check(m.intent == Intent::Engage, "enemy detects visible target");
    m.advance(1,false,20,false);
    check(m.intent == Intent::Investigate, "enemy remembers lost target");
    m.advance(9,false,20,false);
    check(m.intent == Intent::Patrol, "enemy forgets stale target");
    m.advance(0.1,false,20,true);
    check(m.intent == Intent::Investigate, "gunshot triggers investigation");
    m.suppression = 1; m.advance(0.1,true,20,false);
    check(m.intent == Intent::Recover, "suppression interrupts engagement");
    Projectile p{{0,0,0},{0,0,-100}};
    auto start = p.advance(1);
    check(start.z == 0 && p.position.z == -100, "projectile exposes swept segment");
    check(std::abs(p.position.y+4.905) < 1e-6, "gravity matches ballistic trajectory");
    Projectile q{{0,0,0},{0,0,-100}}; q.advance(0.5); q.advance(0.5);
    check(std::abs(q.position.y-p.position.y)<1e-6, "ballistics independent of step size");
    check(damage_at_distance(500,false)>0 && damage_at_distance(0,true)>100, "damage falloff and headshots");
    std::cout << "PASS: weapon, perception, suppression, ballistic invariants\n";
}

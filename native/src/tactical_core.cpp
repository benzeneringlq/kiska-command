#include "tactical_core.hpp"
namespace ridgeline {
bool Weapon::fire() {
    if (reload_left > 0 || cooldown > 0 || rounds <= 0) return false;
    --rounds;
    cooldown = fire_interval;
    return true;
}
bool Weapon::reload() {
    if (reload_left > 0 || rounds == capacity || reserve == 0) return false;
    reload_left = reload_duration;
    return true;
}
void Weapon::advance(double dt) {
    dt = std::max(0.0, dt);
    cooldown = std::max(0.0, cooldown-dt);
    if (reload_left > 0) {
        reload_left = std::max(0.0, reload_left-dt);
        if (reload_left == 0) {
            const int transfer = std::min(capacity-rounds, reserve);
            rounds += transfer;
            reserve -= transfer;
        }
    }
}
void SoldierMind::advance(double dt, bool visible, double distance, bool heard) {
    dt = std::max(0.0, dt);
    suppression = std::max(0.0, suppression-dt*0.22);
    if (visible) {
        awareness = std::min(1.0, awareness + dt * (distance < 30 ? 3.0 : 1.3));
        memory = 8.0;
    } else {
        awareness = std::max(0.0, awareness-dt*0.12);
        memory = std::max(0.0, memory-dt);
        if (heard) { awareness = std::max(awareness,0.4); memory = 6.0; }
    }
    if (suppression > 0.7) intent = Intent::Recover;
    else if (visible && awareness >= 0.75) intent = Intent::Engage;
    else if (memory > 0) intent = Intent::Investigate;
    else intent = Intent::Patrol;
}
double damage_at_distance(double distance, bool headshot) {
    return (headshot ? 2.4 : 1.0) * std::clamp(49.0-distance*0.075,28.0,49.0);
}
}

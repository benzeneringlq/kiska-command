#pragma once
#include <algorithm>
#include <cmath>
#include <cstdint>

namespace ridgeline {
struct Vec3 {
    double x = 0, y = 0, z = 0;
    Vec3 operator+(Vec3 b) const { return {x+b.x,y+b.y,z+b.z}; }
    Vec3 operator*(double s) const { return {x*s,y*s,z*s}; }
};
struct Projectile {
    Vec3 position, velocity;
    double age = 0;
    // Swept collision is performed by the engine between the old and new positions.
    Vec3 advance(double dt) {
        const Vec3 previous = position;
        position = position + velocity*dt + Vec3{0,-4.905*dt*dt,0};
        velocity.y -= 9.81*dt;
        age += dt;
        return previous;
    }
};
struct Weapon {
    int capacity = 30;
    double fire_interval = 0.105, reload_duration = 2.35;
    int rounds = capacity, reserve = 180;
    double cooldown = 0, reload_left = 0;
    bool fire();
    bool reload();
    void advance(double dt);
};
enum class Intent { Patrol, Investigate, Engage, Recover };
struct SoldierMind {
    double awareness = 0, suppression = 0, memory = 0;
    Intent intent = Intent::Patrol;
    void advance(double dt, bool visible, double distance, bool heard);
};
double damage_at_distance(double distance, bool headshot);
} // namespace ridgeline

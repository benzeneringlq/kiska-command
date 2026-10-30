#include "tactical_core.hpp"
#include <godot_cpp/classes/ref_counted.hpp>
#include <godot_cpp/core/class_db.hpp>
#include <godot_cpp/godot.hpp>
#include <godot_cpp/variant/dictionary.hpp>
#include <godot_cpp/variant/array.hpp>
#include <godot_cpp/variant/vector3.hpp>
#include <vector>
#include <map>

using namespace godot;
class TacticalSimulation : public RefCounted {
    GDCLASS(TacticalSimulation, RefCounted);
    std::map<int, ridgeline::Weapon> weapons{{-1, ridgeline::Weapon{}}};
    int current_weapon = -1;
    std::vector<ridgeline::SoldierMind> minds;
protected:
    static void _bind_methods() {
        ClassDB::bind_method(D_METHOD("tick_weapon","delta"), &TacticalSimulation::tick_weapon);
        ClassDB::bind_method(D_METHOD("fire"), &TacticalSimulation::fire);
        ClassDB::bind_method(D_METHOD("reload"), &TacticalSimulation::reload);
        ClassDB::bind_method(D_METHOD("weapon_state"), &TacticalSimulation::weapon_state);
        ClassDB::bind_method(D_METHOD("equip_weapon","id","capacity","interval","reload_duration","reserve"), &TacticalSimulation::equip_weapon);
        ClassDB::bind_method(D_METHOD("perceive","id","delta","visible","distance","heard"), &TacticalSimulation::perceive);
        ClassDB::bind_method(D_METHOD("suppress","id","amount"), &TacticalSimulation::suppress);
        ClassDB::bind_method(D_METHOD("ballistic_step","position","velocity","delta"), &TacticalSimulation::ballistic_step);
        ClassDB::bind_method(D_METHOD("damage","distance","headshot"), &TacticalSimulation::damage);
    }
public:
    bool equip_weapon(int id, int capacity, double interval, double reload_duration, int reserve) {
        if (id < 0 || id > 4095 || capacity < 1 || capacity > 500 ||
                interval < 0.02 || interval > 10 || reload_duration < 0.1 ||
                reload_duration > 30 || reserve < 0 || reserve > 10000 ||
                !std::isfinite(interval) || !std::isfinite(reload_duration)) return false;
        if (id != current_weapon) weapons.at(current_weapon).reload_left = 0;
        if (weapons.count(id) == 0) {
            ridgeline::Weapon weapon;
            weapon.capacity = capacity; weapon.rounds = capacity; weapon.reserve = reserve;
            weapon.fire_interval = interval; weapon.reload_duration = reload_duration;
            weapons.emplace(id, weapon);
        }
        current_weapon = id;
        return true;
    }
    void tick_weapon(double dt) { for (auto &entry : weapons) entry.second.advance(dt); }
    bool fire() { return weapons.at(current_weapon).fire(); }
    bool reload() { return weapons.at(current_weapon).reload(); }
    Dictionary weapon_state() const {
        const auto &weapon = weapons.at(current_weapon);
        Dictionary d; d["rounds"] = weapon.rounds; d["reserve"] = weapon.reserve;
        d["reload"] = weapon.reload_left; d["capacity"] = weapon.capacity;
        d["reload_duration"] = weapon.reload_duration; d["id"] = current_weapon; return d;
    }
    Dictionary perceive(int id, double dt, bool visible, double distance, bool heard) {
        Dictionary d;
        if (id < 0 || id > 4095) return d;
        if (minds.size() <= static_cast<size_t>(id)) minds.resize(id+1);
        auto &m = minds[id]; m.advance(dt,visible,distance,heard);
        d["intent"] = static_cast<int>(m.intent); d["awareness"] = m.awareness;
        d["suppression"] = m.suppression; return d;
    }
    void suppress(int id, double amount) {
        if (id >= 0 && static_cast<size_t>(id) < minds.size())
            minds[id].suppression = std::clamp(minds[id].suppression+amount,0.0,1.0);
    }
    Array ballistic_step(Vector3 position, Vector3 velocity, double dt) const {
        ridgeline::Projectile p{{position.x,position.y,position.z},{velocity.x,velocity.y,velocity.z}};
        p.advance(dt); Array a;
        a.append(Vector3(p.position.x,p.position.y,p.position.z));
        a.append(Vector3(p.velocity.x,p.velocity.y,p.velocity.z)); return a;
    }
    double damage(double distance, bool headshot) const { return ridgeline::damage_at_distance(distance,headshot); }
};
void initialize_ridgeline(ModuleInitializationLevel level) {
    if (level == MODULE_INITIALIZATION_LEVEL_SCENE) ClassDB::register_class<TacticalSimulation>();
}
extern "C" {
GDExtensionBool GDE_EXPORT ridgeline_library_init(GDExtensionInterfaceGetProcAddress get_proc_address,
        GDExtensionClassLibraryPtr library, GDExtensionInitialization *initialization) {
    GDExtensionBinding::InitObject init(get_proc_address,library,initialization);
    init.register_initializer(initialize_ridgeline);
    init.set_minimum_library_initialization_level(MODULE_INITIALIZATION_LEVEL_SCENE);
    return init.init();
}
}

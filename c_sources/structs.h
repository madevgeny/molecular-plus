#ifndef MOLECULAR_STRUCTS_H
#define MOLECULAR_STRUCTS_H

#include <vector>
#include <math.h>

struct Particle;

struct Links{
    float lenght = 0;
    int start = 0;
    int end = 0;
    float stiffness = 0;
    int exponent = 0;
    float damping = 0;
    float broken = 0;
    float estiffness = 0;
    int eexponent = 0;
    float edamping = 0;
    float ebroken = 0;
    float friction = 0;
};

struct ParSys{
    int id = 0;
    int parnum = 0;
    Particle *particles = nullptr;
    int selfcollision_active = 0;
    int othercollision_active = 0;
    int collision_group = 0;
    float friction = 0;
    float collision_damp = 0;
    int links_active = 0;
    float link_length = 0;
    int link_max = 0;
    float link_tension = 0;
    float link_tensionrand = 0;
    float link_stiff = 0;
    float link_stiffrand = 0;
    float link_stiffexp = 0;
    float link_damp = 0;
    float link_damprand = 0;
    float link_broken = 0;
    float link_brokenrand = 0;
    float link_estiff = 0;
    float link_estiffrand = 0;
    float link_estiffexp = 0;
    float link_edamp = 0;
    float link_edamprand = 0;
    float link_ebroken = 0;
    float link_ebrokenrand = 0;
    int relink_group = 0;
    float relink_chance = 0;
    float relink_chancerand = 0;
    int relink_max = 0;
    float relink_tension = 0;
    float relink_tensionrand = 0;
    float relink_stiff = 0;
    float relink_stiffexp = 0;
    float relink_stiffrand = 0;
    float relink_damp = 0;
    float relink_damprand = 0;
    float relink_broken = 0;
    float relink_brokenrand = 0;
    float relink_estiff = 0;
    float relink_estiffexp = 0;
    float relink_estiffrand = 0;
    float relink_edamp = 0;
    float relink_edamprand = 0;
    float relink_ebroken = 0;
    float relink_ebrokenrand = 0;
    float link_friction = 0;
    int link_group = 0;
    int other_link_active = 0;
};

struct Particle{
    int id = 0;
    float loc[3] = {};
    float vel[3] = {};
    float size = 0;
    float mass = 0;
    int state = 0;
    float weak = 0;

    ParSys *sys = nullptr;
    int *collided_with = nullptr;
    int collided_num = 0;
    Links *links = nullptr;
    int links_num = 0;
    int links_activnum = 0;
    int *link_with = nullptr;
    int link_withnum = 0;
    std::vector<int> neighbours;

};

struct SParticle{
    int id = -1;
    float loc[3] = {};
};


struct Node{
    int index = 0;
    char name = 0;
    int parent = 0;
    float loc[3] = {};
    SParticle *particle = nullptr;
    Node *left_child = nullptr;
    Node *right_child = nullptr;
};


struct KDTree{
    int numnodes = 0;
    Node *root_node = nullptr;
    Node *nodes = nullptr;
    char axis[64] = {};
    int thread_index = 0;
    int *thread_nodes = nullptr;
    int *thread_start = nullptr;
    int *thread_end = nullptr;
    int *thread_name = nullptr;
    int *thread_parent = nullptr;
    int *thread_depth = nullptr;
};


#endif
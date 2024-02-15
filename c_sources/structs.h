#ifndef MOLECULAR_STRUCTS_H
#define MOLECULAR_STRUCTS_H

#include <math.h>

struct SParticle{
    int id = -1;
    float loc[3] = {};
};


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
#ifndef MOLECULAR_KDTREE_H
#define MOLECULAR_KDTREE_H

#include <vector>
#include <math.h>

struct SParticle;

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

extern KDTree *kdtree;
#endif
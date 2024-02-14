#ifndef MOLECULAR_MATH_UTILS_H
#define MOLECULAR_MATH_UTILS_H

#include <math.h>

#ifdef _MSC_VER 
#define MOLECULAR_FORCE_INLINE  __forceinline
#else
#define MOLECULAR_FORCE_INLINE inline __attribute__((always_inline))
#endif

#include "structs.h"

/*
cdef extern from "math_utils.h":
    float dot_product(float u[3],float v[3])noexcept nogil
    float square_dist(float p1[3], float p2[3])noexcept nogil
    int arraysearch(int element, int *array, int len)noexcept nogil
    void quick_sort(SParticle *a, int n, int axis)noexcept nogil

*/

MOLECULAR_FORCE_INLINE float dot_product(float u[3],float v[3]){
    float dot = (u[0] * v[0]) + (u[1] * v[1]) + (u[2] * v[2]);
    return dot;
}

MOLECULAR_FORCE_INLINE float square_dist(float p1[3], float p2[3]){
    float d = p1[0] - p2[0];
    float sq_dist = d * d;
    d = p1[1] - p2[1];
    sq_dist += d * d;
    d = p1[2] - p2[2];
    sq_dist += d * d;
    return sq_dist;
}

MOLECULAR_FORCE_INLINE int arraysearch(int element, int *array, int len){
    int i = 0;
    for(int i = 0; i < len; ++i){
        if(element == array[i]){
            return i;
        }
    }
    return -1;
}

inline void quick_sort(SParticle *a, int n, int axis){
    if(n < 2){
        return;
    }

    SParticle t;
    float p = a[n / 2].loc[axis];
    SParticle *l = a;
    SParticle *r = a + n - 1;
    while(l <= r){
        if(l[0].loc[axis] < p){
            l += 1;
            continue;
        }

        if(r[0].loc[axis] > p){
            r -= 1;
            // we need to check the condition (l <= r) every time
            // we change the value of l or r
            continue;
        }

        t = l[0];
        l[0] = r[0];
        l += 1;
        r[0] = t;
        r -= 1;
    }

    quick_sort(a, r - a + 1, axis);
    quick_sort(l, a + n - l, axis);
}

#endif
#ifndef MATH_UTILS_H
#define MATH_UTILS_H

#include <math.h>

#ifdef _MSC_VER 
#define MOLECULAR_FORCE_INLINE  __forceinline
#else
#define MOLECULAR_FORCE_INLINE inline __attribute__((always_inline))
#endif

/*
cdef extern from "math_utils.h":
    float dot_product(float u[3],float v[3])noexcept nogil
    float square_dist(float p1[3], float p2[3])noexcept nogil
    int arraysearch(int element, int *array, int len)noexcept nogil

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

#endif
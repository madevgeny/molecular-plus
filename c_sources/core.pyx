#cython: profile=False
#cython: boundscheck=False
#cython: wraparound=False
#cython: cdivision=True
#cython: language_level=3
#cython: cpow=True

# distutils: language = c++

# NOTE: order of slow fonction to be optimize/multithreaded:
# kdtreesearching, kdtreecreating, linksolving


cimport cython
try:
    from time import process_time as clock
except ImportError:
    from time import clock
from cython.parallel import parallel, prange, threadid
from libc.stdlib cimport malloc, realloc, free, rand, srand, abs
from libc.math cimport fabs, sqrtf

cdef extern from "<vector>" namespace "std":
    cdef cppclass vector[T]:
        cppclass iterator:
            T operator*()nogil
            iterator operator++()nogil
            bint operator==(iterator)nogil
            bint operator!=(iterator)nogil
        vector()nogil
        void push_back(T&)nogil
        size_t size()nogil
        void reserve(size_t n)nogil
        void clear()nogil
        T* data()nogil
        T& operator[](int)nogil
        T& at(int)nogil
        iterator begin()nogil
        iterator end()nogil


cdef extern from *:
    int INT_MAX
    float FLT_MAX


cdef extern from "math_utils.h":
    float dot_product(float u[3],float v[3])noexcept nogil
    float square_dist(float p1[3], float p2[3])noexcept nogil
    int arraysearch(int element, int *array, int len)noexcept nogil
    void quick_sort(SParticle *a, int n, int axis)noexcept nogil

cdef extern from "structs.h":
    cdef struct SParticle:
        int id
        float loc[3]

    cdef struct Links:
        float lenght
        int start
        int end
        float stiffness
        int exponent
        float damping
        float broken
        float estiffness
        int eexponent
        float edamping
        float ebroken
        float friction

    cdef struct ParSys:
        int id
        int parnum
        Particle *particles
        int selfcollision_active
        int othercollision_active
        int collision_group
        float friction
        float collision_damp
        int links_active
        float link_length
        int link_max
        float link_tension
        float link_tensionrand
        float link_stiff
        float link_stiffrand
        float link_stiffexp
        float link_damp
        float link_damprand
        float link_broken
        float link_brokenrand
        float link_estiff
        float link_estiffrand
        float link_estiffexp
        float link_edamp
        float link_edamprand
        float link_ebroken
        float link_ebrokenrand
        int relink_group
        float relink_chance
        float relink_chancerand
        int relink_max
        float relink_tension
        float relink_tensionrand
        float relink_stiff
        float relink_stiffexp
        float relink_stiffrand
        float relink_damp
        float relink_damprand
        float relink_broken
        float relink_brokenrand
        float relink_estiff
        float relink_estiffexp
        float relink_estiffrand
        float relink_edamp
        float relink_edamprand
        float relink_ebroken
        float relink_ebrokenrand
        float link_friction
        int link_group
        int other_link_active


    cdef struct Particle:
        int id
        float loc[3]
        float vel[3]
        float size
        float mass
        int state
        float weak

        ParSys *sys
        vector[int] collided_with
        Links *links
        int links_num
        int links_activnum
        int *link_with
        int link_withnum
        vector[int] neighbours


cdef extern from "kdtree.h":
    cdef KDTree *kdtree
    cdef struct KDTree:
        int numnodes
        # int num_result
        # int *result
        Node *root_node
        Node *nodes
        char axis[64]
        int thread_index
        int *thread_nodes
        int *thread_start
        int *thread_end
        int *thread_name
        int *thread_parent
        int *thread_depth

    cdef struct Node:
        int index
        char name
        int parent
        float loc[3]
        SParticle *particle
        Node *left_child
        Node *right_child


cdef float fps = 0
cdef int substep = 0
cdef float deltatime = 0
cdef int parnum = 0
cdef int psysnum = 0
cdef int cpunum = 0
cdef int newlinks = 0
cdef int totallinks = 0
cdef int totaldeadlinks = 0
cdef int *deadlinks = NULL
cdef Particle *parlist = NULL
cdef SParticle *parlistcopy = NULL
cdef ParSys *psys = NULL

print("cmolcore imported  v1.14.3")


cpdef init(importdata):
    global fps
    global substep
    global deltatime
    global parnum
    global parlist
    global parlistcopy
    global kdtree
    global psysnum
    global psys
    global cpunum
    global newlinks
    global totallinks
    global totaldeadlinks
    global deadlinks
    cdef int i = 0
    cdef int ii = 0
    cdef int profiling = 0

    newlinks = 0
    totallinks = 0
    totaldeadlinks = 0
    fps = float(importdata[0][0])
    substep = int(importdata[0][1])
    deltatime = (fps * (substep + 1))
    psysnum = importdata[0][2]
    parnum = importdata[0][3]
    cpunum = importdata[0][4]
    deadlinks = <int *>malloc(cpunum * cython.sizeof(int))
    print("  Number of cpu's used:", cpunum)
    psys = <ParSys *>malloc(psysnum * cython.sizeof(ParSys))
    parlist = <Particle *>malloc(parnum * cython.sizeof(Particle))
    parlistcopy = <SParticle *>malloc(parnum * cython.sizeof(SParticle))
    cdef int jj = 0

    for i in range(psysnum):
        psys[i].id = i
        psys[i].parnum = importdata[i + 1][0]
        psys[i].particles = &parlist[jj]
        psys[i].selfcollision_active = importdata[i + 1][6][0]
        psys[i].othercollision_active = importdata[i + 1][6][1]
        psys[i].collision_group = importdata[i + 1][6][2]
        psys[i].friction = importdata[i + 1][6][3]
        psys[i].collision_damp = importdata[i + 1][6][4]
        psys[i].links_active = importdata[i + 1][6][5]
        psys[i].link_length = importdata[i + 1][6][6]
        psys[i].link_max = importdata[i + 1][6][7]
        psys[i].link_tension = importdata[i + 1][6][8]
        psys[i].link_tensionrand = importdata[i + 1][6][9]
        psys[i].link_stiff = importdata[i + 1][6][10] * 0.5
        psys[i].link_stiffrand = importdata[i + 1][6][11]
        psys[i].link_stiffexp = importdata[i + 1][6][12]
        psys[i].link_damp = importdata[i + 1][6][13]
        psys[i].link_damprand = importdata[i + 1][6][14]
        psys[i].link_broken = importdata[i + 1][6][15]
        psys[i].link_brokenrand = importdata[i + 1][6][16]
        psys[i].link_estiff = importdata[i + 1][6][17] * 0.5
        psys[i].link_estiffrand = importdata[i + 1][6][18]
        psys[i].link_estiffexp = importdata[i + 1][6][19]
        psys[i].link_edamp = importdata[i + 1][6][20]
        psys[i].link_edamprand = importdata[i + 1][6][21]
        psys[i].link_ebroken = importdata[i + 1][6][22]
        psys[i].link_ebrokenrand = importdata[i + 1][6][23]
        psys[i].relink_group = importdata[i + 1][6][24]
        psys[i].relink_chance = importdata[i + 1][6][25]
        psys[i].relink_chancerand = importdata[i + 1][6][26]
        psys[i].relink_max = importdata[i + 1][6][27]
        psys[i].relink_tension = importdata[i + 1][6][28]
        psys[i].relink_tensionrand = importdata[i + 1][6][29]
        psys[i].relink_stiff = importdata[i + 1][6][30] * 0.5
        psys[i].relink_stiffexp = importdata[i + 1][6][31]
        psys[i].relink_stiffrand = importdata[i + 1][6][32]
        psys[i].relink_damp = importdata[i + 1][6][33]
        psys[i].relink_damprand = importdata[i + 1][6][34]
        psys[i].relink_broken = importdata[i + 1][6][35]
        psys[i].relink_brokenrand = importdata[i + 1][6][36]
        psys[i].relink_estiff = importdata[i + 1][6][37] * 0.5
        psys[i].relink_estiffexp = importdata[i + 1][6][38]
        psys[i].relink_estiffrand = importdata[i + 1][6][39]
        psys[i].relink_edamp = importdata[i + 1][6][40]
        psys[i].relink_edamprand = importdata[i + 1][6][41]
        psys[i].relink_ebroken = importdata[i + 1][6][42]
        psys[i].relink_ebrokenrand = importdata[i + 1][6][43]
        psys[i].link_friction = importdata[i + 1][6][44]
        psys[i].link_group = importdata[i + 1][6][45]
        psys[i].other_link_active = importdata[i + 1][6][46]

        for ii in range(psys[i].parnum):
            parlist[jj].id = jj
            parlist[jj].loc[0] = importdata[i + 1][1][(ii * 3)]
            parlist[jj].loc[1] = importdata[i + 1][1][(ii * 3) + 1]
            parlist[jj].loc[2] = importdata[i + 1][1][(ii * 3) + 2]
            parlist[jj].vel[0] = importdata[i + 1][2][(ii * 3)]
            parlist[jj].vel[1] = importdata[i + 1][2][(ii * 3) + 1]
            parlist[jj].vel[2] = importdata[i + 1][2][(ii * 3) + 2]
            parlist[jj].size = importdata[i + 1][3][ii]
            parlist[jj].mass = importdata[i + 1][4][ii]
            parlist[jj].state = importdata[i + 1][5][ii]
            parlist[jj].weak = importdata[i + 1][7][ii]
            parlist[jj].sys = &psys[i]
            parlist[jj].collided_with.reserve(16)
            parlist[jj].neighbours.reserve(128)
            parlist[jj].links = <Links *>malloc(1 * cython.sizeof(Links))
            parlist[jj].links_num = 0
            parlist[jj].links_activnum = 0
            parlist[jj].link_with = <int *>malloc(1 * cython.sizeof(int))
            parlist[jj].link_withnum = 0
           
            jj += 1

    jj = 0
    kdtree = <KDTree *>malloc(1 * cython.sizeof(KDTree))
    KDTree_create_nodes(kdtree, parnum)

    with nogil:
        for i in prange(
                        parnum,
                        schedule='dynamic',
                        chunksize=10,
                        num_threads=cpunum
                        ):
            parlistcopy[i].id = parlist[i].id
            parlistcopy[i].loc = parlist[i].loc

            #parlistcopy[i].loc[0] = parlist[i].loc[0]
            #parlistcopy[i].loc[1] = parlist[i].loc[1]
            #parlistcopy[i].loc[2] = parlist[i].loc[2]

    KDTree_create_tree(kdtree, parlistcopy, 0, parnum - 1, 0, -1, 0, 1)

    with nogil:
        for i in prange(kdtree.thread_index, schedule='dynamic', chunksize=10,num_threads=cpunum):
            KDTree_create_tree(
                kdtree,
                parlistcopy,
                kdtree.thread_start[i],
                kdtree.thread_end[i],
                kdtree.thread_name[i],
                kdtree.thread_parent[i],
                kdtree.thread_depth[i],
                0
            )

    with nogil:
        for i in prange(
                        parnum,
                        schedule='dynamic',
                        chunksize=10,
                        num_threads=cpunum
                        ):
            if parlist[i].sys.links_active == 1:
                KDTree_rnn_query(
                    kdtree,
                    &parlist[i],
                    parlist[i].loc,
                    parlist[i].sys.link_length
                )

    for i in range(parnum):
        create_link(parlist[i].id, parlist[i].sys.link_max)
        parlist[i].neighbours.clear()
    totallinks += newlinks
    print("  New links created: ", newlinks)
    return parnum

cpdef simulate(importdata):
    global kdtree
    global parlist
    global parlistcopy
    global parnum
    global psysnum
    global psys
    global cpunum
    global deltatime
    global newlinks
    global totallinks
    global totaldeadlinks
    global deadlinks

    cdef int i = 0
    cdef int ii = 0
    cdef int profiling = 0
    cdef float minX = INT_MAX
    cdef float minY = INT_MAX
    cdef float minZ = INT_MAX
    cdef float maxX = -INT_MAX
    cdef float maxY = -INT_MAX
    cdef float maxZ = -INT_MAX
    cdef float maxSize = -INT_MAX
    cdef Pool *parPool = <Pool *>malloc(1 * cython.sizeof(Pool))
    parPool.parity = <Parity *>malloc(2 * cython.sizeof(Parity))
    parPool[0].axis = -1
    parPool[0].offset = 0
    parPool[0].max = 0

    newlinks = 0
    for i in range(cpunum):
        deadlinks[i] = 0
    if profiling == 1:
        print("-->start simulate")
        stime2 = clock()
        stime = clock()

    update(importdata)

    if profiling == 1:
        print("-->update time", clock() - stime, "sec")
        stime = clock()

    for i in range(parnum):
        parlistcopy[i].id = parlist[i].id

        parlistcopy[i].loc[0] = parlist[i].loc[0]
        if parlist[i].loc[0] < minX:
            minX = parlist[i].loc[0]
        if parlist[i].loc[0] > maxX:
            maxX = parlist[i].loc[0]

        parlistcopy[i].loc[1] = parlist[i].loc[1]
        if parlist[i].loc[1] < minY:
            minY = parlist[i].loc[1]
        if parlist[i].loc[1] > maxY:
            maxY = parlist[i].loc[1]

        parlistcopy[i].loc[2] = parlist[i].loc[2]
        if parlist[i].loc[2] < minZ:
            minZ = parlist[i].loc[2]
        if parlist[i].loc[2] > maxZ:
            maxZ = parlist[i].loc[2]

        if parlist[i].sys.links_active == 1:
            if parlist[i].links_num > 0:
                for ii in range(parlist[i].links_num):
                    if parlist[i].links[ii].lenght > maxSize:
                        maxSize = parlist[i].links[ii].lenght

        if (parlist[i].size * 2) > maxSize:
            maxSize = (parlist[i].size * 2)

    if (maxX - minX) >= (maxY - minY) and (maxX - minX) >= (maxZ - minZ):
        parPool[0].axis = 0
        parPool[0].offset = 0 - minX
        parPool[0].max = maxX + parPool[0].offset

    if (maxY - minY) > (maxX - minX) and (maxY - minY) > (maxZ - minZ):
        parPool[0].axis = 1
        parPool[0].offset = 0 - minY
        parPool[0].max = maxY + parPool[0].offset

    if (maxZ - minZ) > (maxY - minY) and (maxZ - minZ) > (maxX - minX):
        parPool[0].axis = 2
        parPool[0].offset = 0 - minZ
        parPool[0].max = maxZ + parPool[0].offset

    if (parPool[0].max / ( cpunum * 10 )) > maxSize:
        maxSize = (parPool[0].max / ( cpunum * 10 ))


    cdef int pair
    cdef int heaps
    cdef float scale = 1 / ( maxSize * 2.1 )

    for pair in range(2):

        parPool[0].parity[pair].heap = \
            <Heap *>malloc((<int>(parPool[0].max * scale) + 1) * \
            cython.sizeof(Heap))

        for heaps in range(<int>(parPool[0].max * scale) + 1):
            parPool[0].parity[pair].heap[heaps].parnum = 0
            parPool[0].parity[pair].heap[heaps].maxalloc = 50

            parPool[0].parity[pair].heap[heaps].par = \
                <int *>malloc(parPool[0].parity[pair].heap[heaps].maxalloc * \
                cython.sizeof(int))

    for i in range(parnum):
        pair = <int>(((
            parlist[i].loc[parPool[0].axis] + parPool[0].offset) * scale) % 2
        )
        heaps = <int>((
            parlist[i].loc[parPool[0].axis] + parPool[0].offset) * scale
        )
        parPool[0].parity[pair].heap[heaps].parnum += 1

        if parPool[0].parity[pair].heap[heaps].parnum > \
                parPool[0].parity[pair].heap[heaps].maxalloc:

            parPool[0].parity[pair].heap[heaps].maxalloc = \
                <int>(parPool[0].parity[pair].heap[heaps].maxalloc * 1.25)

            parPool[0].parity[pair].heap[heaps].par = \
                <int *>realloc(
                    parPool[0].parity[pair].heap[heaps].par,
                    (parPool[0].parity[pair].heap[heaps].maxalloc + 2 ) * \
                    cython.sizeof(int)
                )

        parPool[0].parity[pair].heap[heaps].par[
            (parPool[0].parity[pair].heap[heaps].parnum - 1)] = parlist[i].id

    if profiling == 1:
        print("-->copy data time", clock() - stime, "sec")
        stime = clock()

    KDTree_create_tree(kdtree, parlistcopy, 0, parnum - 1, 0, -1, 0, 1)

    with nogil:
        for i in prange(
                        kdtree.thread_index,
                        schedule='dynamic',
                        chunksize=10,
                        num_threads=cpunum
                        ):
            KDTree_create_tree(
                kdtree,
                parlistcopy,
                kdtree.thread_start[i],
                kdtree.thread_end[i],
                kdtree.thread_name[i],
                kdtree.thread_parent[i],
                kdtree.thread_depth[i],
                0
            )

    if profiling == 1:
        print("-->create tree time", clock() - stime,"sec")
        stime = clock()

    with nogil:
        for i in prange(
                        parnum,
                        schedule='dynamic',
                        chunksize=10,
                        num_threads=cpunum
                        ):
            KDTree_rnn_query(
                kdtree,
                &parlist[i],
                parlist[i].loc,
                parlist[i].size * 2
            )

    if profiling == 1:
        print("-->neighbours time", clock() - stime, "sec")
        stime = clock()

    with nogil:
        for pair in range(2):
            for heaps in prange(
                                <int>(parPool[0].max * scale) + 1,
                                schedule='dynamic',
                                chunksize=1,
                                num_threads=cpunum
                                ):
                for i in range(parPool[0].parity[pair].heap[heaps].parnum):

                    collide(
                        &parlist[parPool[0].parity[pair].heap[heaps].par[i]]
                    )

                    solve_link(
                        &parlist[parPool[0].parity[pair].heap[heaps].par[i]]
                    )

                    parlist[
                        parPool[0].parity[pair].heap[heaps].par[i]
                    ].neighbours.clear()


    if profiling == 1:
        print("-->collide/solve link time", clock() - stime, "sec")
        stime = clock()

    exportdata = []
    parloc = []
    parvel = []
    parloctmp = []
    parveltmp = []

    for i in range(psysnum):
        for ii in range(psys[i].parnum):
            parloctmp.append(psys[i].particles[ii].loc[0])
            parloctmp.append(psys[i].particles[ii].loc[1])
            parloctmp.append(psys[i].particles[ii].loc[2])
            parveltmp.append(psys[i].particles[ii].vel[0])
            parveltmp.append(psys[i].particles[ii].vel[1])
            parveltmp.append(psys[i].particles[ii].vel[2])
        parloc.append(parloctmp)
        parvel.append(parveltmp)
        parloctmp = []
        parveltmp = []

    totallinks += newlinks
    pydeadlinks = 0
    for i in range(cpunum):
        pydeadlinks += deadlinks[i]
    totaldeadlinks += pydeadlinks

    exportdata = [
        parloc,
        parvel,
        newlinks,
        pydeadlinks,
        totallinks,
        totaldeadlinks
    ]

    if profiling == 1:
        print("-->export time", clock() - stime, "sec")
        print("-->all process time", clock() - stime2, "sec")
    return exportdata


cpdef memfree():
    global kdtree
    global psysnum
    global parnum
    global psys
    global parlist
    global parlistcopy
    global fps
    global substep
    global deadlinks
    cdef int i = 0

    fps = 0
    substep = 0
    deltatime = 0
    cpunum = 0
    newlinks = 0
    totallinks = 0
    totaldeadlinks = 0
    free(deadlinks)
    deadlinks = NULL

    for i in range(parnum):
        if parlist[i].links_num >= 1:
            free(parlist[i].links)
            parlist[i].links = NULL
            parlist[i].links_num = 0
            parlist[i].links_activnum = 0
        if parlist[i].link_withnum >= 1:
            free(parlist[i].link_with)
            parlist[i].link_with = NULL
            parlist[i].link_withnum = 0
            
        parlist[i].collided_with.clear()
        parlist[i].neighbours.clear()

    for i in range(psysnum):
        if psysnum >= 1:
            psys[i].particles = NULL

    if psysnum >= 1:
        free(psys)
        psys = NULL

    if parnum >= 1:
        free(parlistcopy)
        parlistcopy = NULL
        free(parlist)
        parlist = NULL

    parnum = 0
    psysnum = 0

    if kdtree.numnodes >= 1:
        for i in range(kdtree.numnodes):
            free(kdtree.nodes[i].particle)
            kdtree.nodes[i].particle = NULL
            free(kdtree.nodes[i].left_child)
            kdtree.nodes[i].left_child = NULL
            free(kdtree.nodes[i].right_child)
            kdtree.nodes[i].right_child = NULL

        free(kdtree.thread_nodes)
        kdtree.thread_nodes = NULL
        free(kdtree.thread_start)
        kdtree.thread_start = NULL
        free(kdtree.thread_end)
        kdtree.thread_end = NULL
        free(kdtree.thread_name)
        kdtree.thread_name = NULL
        free(kdtree.thread_parent)
        kdtree.thread_parent = NULL
        free(kdtree.thread_depth)
        kdtree.thread_depth = NULL
        free(kdtree.nodes)
        kdtree.nodes = NULL
        free(kdtree.root_node)
        kdtree.root_node = NULL

    free(kdtree)
    kdtree = NULL


#@cython.cdivision(True)
cdef void collide(Particle *par)noexcept nogil:
    global kdtree
    global deltatime
    global deadlinks
    cdef Particle *par2 = NULL
    cdef float stiff = 0
    cdef float target = 0
    cdef float sqtarget = 0
    cdef float lenghtx = 0
    cdef float lenghty = 0
    cdef float lenghtz = 0
    cdef float sqlenght = 0
    cdef float lenght = 0
    cdef float invlenght = 0
    cdef float factor = 0
    cdef float ratio1 = 0
    cdef float ratio2 = 0
    cdef float factor1 = 0
    cdef float factor2 = 0
    cdef float *col_normal1 = [0, 0, 0]
    cdef float *col_normal2 = [0, 0, 0]
    cdef float *ypar_vel = [0, 0, 0]
    cdef float *xpar_vel = [0, 0, 0]
    cdef float *yi_vel = [0, 0, 0]
    cdef float *xi_vel = [0, 0, 0]
    cdef float friction1 = 0
    cdef float friction2 = 0
    cdef float damping1 = 0
    cdef float damping2 = 0
    cdef int i = 0
    cdef int check = 0
    cdef float Ua = 0
    cdef float Ub = 0
    cdef float Cr = 0
    cdef float Ma = 0
    cdef float Mb = 0
    cdef float Va = 0
    cdef float Vb = 0
    cdef float force1 = 0
    cdef float force2 = 0
    cdef float mathtmp = 0

    if  par.state < 3:
        return
    if par.sys.selfcollision_active == False and par.sys.othercollision_active == False:
        return

    # for i in range(kdtree.num_result):
    for i in range(par.neighbours.size()):
        check = 0
        if parlist[i].id == -1:
            check += 1
        par2 = &parlist[par.neighbours[i]]
        if par.id == par2.id:
            check += 10
        if arraysearch(par2.id, par.collided_with.data(), par.collided_with.size()) == -1:
        # if par2 not in par.collided_with:
            if par2.sys.id != par.sys.id :
                if par2.sys.othercollision_active == False or \
                        par.sys.othercollision_active == False:
                    check += 100

            if par2.sys.collision_group != par.sys.collision_group:
                check += 1000

            if par2.sys.id == par.sys.id and \
                    par.sys.selfcollision_active == False:
                check += 10000

            stiff = deltatime
            target = (par.size + par2.size) * 0.999
            sqtarget = target * target

            if check == 0 and par2.state >= 3 and \
                    arraysearch(
                        par2.id, par.link_with, par.link_withnum
                    ) == -1 and \
                    arraysearch(
                        par.id, par2.link_with, par2.link_withnum
                    ) == -1:

            # if par.state <= 1 and par2.state <= 1 and \
            #       par2 not in par.link_with and par not in par2.link_with:
                lenghtx = par.loc[0] - par2.loc[0]
                lenghty = par.loc[1] - par2.loc[1]
                lenghtz = par.loc[2] - par2.loc[2]
                sqlenght  = square_dist(par.loc, par2.loc)
                if sqlenght != 0 and sqlenght < sqtarget:
                    lenght = sqrtf(sqlenght)
                    invlenght = 1 / lenght
                    factor = (lenght - target) * invlenght
                    ratio1 = (par2.mass / (par.mass + par2.mass))
                    ratio2 = 1 - ratio1

                    mathtmp = factor * stiff
                    force1 = ratio1 * mathtmp
                    force2 = ratio2 * mathtmp
                    par.vel[0] -= lenghtx * force1
                    par.vel[1] -= lenghty * force1
                    par.vel[2] -= lenghtz * force1
                    par2.vel[0] += lenghtx * force2
                    par2.vel[1] += lenghty * force2
                    par2.vel[2] += lenghtz * force2

                    col_normal1[0] = (par2.loc[0] - par.loc[0]) * invlenght
                    col_normal1[1] = (par2.loc[1] - par.loc[1]) * invlenght
                    col_normal1[2] = (par2.loc[2] - par.loc[2]) * invlenght
                    col_normal2[0] = col_normal1[0] * -1
                    col_normal2[1] = col_normal1[1] * -1
                    col_normal2[2] = col_normal1[2] * -1

                    factor1 = dot_product(par.vel,col_normal1)

                    ypar_vel[0] = factor1 * col_normal1[0]
                    ypar_vel[1] = factor1 * col_normal1[1]
                    ypar_vel[2] = factor1 * col_normal1[2]
                    xpar_vel[0] = par.vel[0] - ypar_vel[0]
                    xpar_vel[1] = par.vel[1] - ypar_vel[1]
                    xpar_vel[2] = par.vel[2] - ypar_vel[2]

                    factor2 = dot_product(par2.vel, col_normal2)

                    yi_vel[0] = factor2 * col_normal2[0]
                    yi_vel[1] = factor2 * col_normal2[1]
                    yi_vel[2] = factor2 * col_normal2[2]
                    xi_vel[0] = par2.vel[0] - yi_vel[0]
                    xi_vel[1] = par2.vel[1] - yi_vel[1]
                    xi_vel[2] = par2.vel[2] - yi_vel[2]

                    friction1 = 1 - (((
                        par.sys.friction + par2.sys.friction) * 0.5) * ratio1
                    )

                    friction2 = 1 - (((
                        par.sys.friction + par2.sys.friction) * 0.5) * ratio2
                    )

                    damping1 = 1 - (((
                        par.sys.collision_damp + par2.sys.collision_damp
                    ) * 0.5) * ratio1)

                    damping2 = 1 - (((
                        par.sys.collision_damp + par2.sys.collision_damp
                    ) * 0.5) * ratio2)

                    par.vel[0] = ((ypar_vel[0] * damping1) + (yi_vel[0] * \
                        (1 - damping1))) + ((xpar_vel[0] * friction1) + \
                        ( xi_vel[0] * ( 1 - friction1)))

                    par.vel[1] = ((ypar_vel[1] * damping1) + (yi_vel[1] * \
                        (1 - damping1))) + ((xpar_vel[1] * friction1) + \
                        ( xi_vel[1] * ( 1 - friction1)))

                    par.vel[2] = ((ypar_vel[2] * damping1) + (yi_vel[2] * \
                        (1 - damping1))) + ((xpar_vel[2] * friction1) + \
                        ( xi_vel[2] * ( 1 - friction1)))

                    par2.vel[0] = ((yi_vel[0] * damping2) + (ypar_vel[0] * \
                        (1 - damping2))) + ((xi_vel[0] * friction2) + \
                        ( xpar_vel[0] * ( 1 - friction2)))

                    par2.vel[1] = ((yi_vel[1] * damping2) + (ypar_vel[1] * \
                        (1 - damping2))) + ((xi_vel[1] * friction2) + \
                        ( xpar_vel[1] * ( 1 - friction2)))

                    par2.vel[2] = ((yi_vel[2] * damping2) + (ypar_vel[2] * \
                        (1 - damping2))) + ((xi_vel[2] * friction2) + \
                        ( xpar_vel[2] * ( 1 - friction2)))

                    par2.collided_with.push_back(par.id)

                    if ((par.sys.relink_chance + par2.sys.relink_chance) / 2) \
                            > 0:
                        create_link(par.id,par.sys.link_max * 2, par2.id)


cdef void solve_link(Particle *par)noexcept nogil:
    global parlist
    global deltatime
    global deadlinks
    cdef int i = 0
    cdef float stiff = 0
    cdef float damping = 0
    cdef float timestep = 0
    cdef float exp = 0
    cdef Particle *par1 = NULL
    cdef Particle *par2 = NULL
    cdef float *Loc1 = [0, 0, 0]
    cdef float *Loc2 = [0, 0, 0]
    cdef float *V1 = [0, 0, 0]
    cdef float *V2 = [0, 0, 0]
    cdef float LengthX = 0
    cdef float LengthY = 0
    cdef float LengthZ = 0
    cdef float Length = 0
    cdef float Vx = 0
    cdef float Vy = 0
    cdef float Vz = 0
    cdef float V = 0
    cdef float ForceSpring = 0
    cdef float ForceDamper = 0
    cdef float ForceX = 0
    cdef float ForceY = 0
    cdef float ForceZ = 0
    cdef float *Force1 = [0, 0, 0]
    cdef float *Force2 = [0, 0, 0]
    cdef float ratio1 = 0
    cdef float ratio2 = 0
    cdef int parsearch = 0
    cdef int par2search = 0
    cdef float *normal1 = [0, 0, 0]
    cdef float *normal2 = [0, 0, 0]
    cdef float factor1 = 0
    cdef float factor2 = 0
    cdef float friction1 = 0
    cdef float friction2 = 0
    cdef float *ypar1_vel = [0, 0, 0]
    cdef float *xpar1_vel = [0, 0, 0]
    cdef float *ypar2_vel = [0, 0, 0]
    cdef float *xpar2_vel = [0, 0, 0]
    # broken_links = []
    if  par.state < 3:
        return
    for i in range(par.links_num):
        if par.links[i].start != -1:
            par1 = &parlist[par.links[i].start]
            par2 = &parlist[par.links[i].end]
            Loc1[0] = par1.loc[0]
            Loc1[1] = par1.loc[1]
            Loc1[2] = par1.loc[2]
            Loc2[0] = par2.loc[0]
            Loc2[1] = par2.loc[1]
            Loc2[2] = par2.loc[2]
            V1[0] = par1.vel[0]
            V1[1] = par1.vel[1]
            V1[2] = par1.vel[2]
            V2[0] = par2.vel[0]
            V2[1] = par2.vel[1]
            V2[2] = par2.vel[2]
            LengthX = Loc2[0] - Loc1[0]
            LengthY = Loc2[1] - Loc1[1]
            LengthZ = Loc2[2] - Loc1[2]
            Length = (LengthX ** 2 + LengthY ** 2 + LengthZ ** 2) ** (0.5)
            if par.links[i].lenght != Length and Length != 0:
                if par.links[i].lenght > Length:
                    stiff = par.links[i].stiffness * deltatime
                    damping = par.links[i].damping
                    exp = par.links[i].exponent
                if par.links[i].lenght < Length:
                    stiff = par.links[i].estiffness * deltatime
                    damping = par.links[i].edamping
                    exp = par.links[i].eexponent
                Vx = V2[0] - V1[0]
                Vy = V2[1] - V1[1]
                Vz = V2[2] - V1[2]
                V = (Vx * LengthX + Vy * LengthY + Vz * LengthZ) / Length
                ForceSpring = ((Length - par.links[i].lenght) ** (exp)) * stiff
                ForceDamper = damping * V
                ForceX = (ForceSpring + ForceDamper) * LengthX / Length
                ForceY = (ForceSpring + ForceDamper) * LengthY / Length
                ForceZ = (ForceSpring + ForceDamper) * LengthZ / Length
                Force1[0] = ForceX
                Force1[1] = ForceY
                Force1[2] = ForceZ
                Force2[0] = -ForceX
                Force2[1] = -ForceY
                Force2[2] = -ForceZ
                ratio1 = (par2.mass/(par1.mass + par2.mass))
                ratio2 = (par1.mass/(par1.mass + par2.mass))

                if par1.state == 1: #dead particle, correct velocity ratio of alive partner
                    ratio1 = 0
                    ratio2 = 1
                elif par2.state == 1:
                    ratio1 = 1
                    ratio2 = 0

                par1.vel[0] += Force1[0] * ratio1
                par1.vel[1] += Force1[1] * ratio1
                par1.vel[2] += Force1[2] * ratio1
                par2.vel[0] += Force2[0] * ratio2
                par2.vel[1] += Force2[1] * ratio2
                par2.vel[2] += Force2[2] * ratio2

                normal1[0] = LengthX / Length
                normal1[1] = LengthY / Length
                normal1[2] = LengthZ / Length
                normal2[0] = normal1[0] * -1
                normal2[1] = normal1[1] * -1
                normal2[2] = normal1[2] * -1

                factor1 = dot_product(par1.vel, normal1)

                ypar1_vel[0] = factor1 * normal1[0]
                ypar1_vel[1] = factor1 * normal1[1]
                ypar1_vel[2] = factor1 * normal1[2]
                xpar1_vel[0] = par1.vel[0] - ypar1_vel[0]
                xpar1_vel[1] = par1.vel[1] - ypar1_vel[1]
                xpar1_vel[2] = par1.vel[2] - ypar1_vel[2]

                factor2 = dot_product(par2.vel, normal2)

                ypar2_vel[0] = factor2 * normal2[0]
                ypar2_vel[1] = factor2 * normal2[1]
                ypar2_vel[2] = factor2 * normal2[2]
                xpar2_vel[0] = par2.vel[0] - ypar2_vel[0]
                xpar2_vel[1] = par2.vel[1] - ypar2_vel[1]
                xpar2_vel[2] = par2.vel[2] - ypar2_vel[2]

                friction1 = 1 - ((par.links[i].friction) * ratio1)
                friction2 = 1 - ((par.links[i].friction) * ratio2)

                par1.vel[0] = ypar1_vel[0] + ((xpar1_vel[0] * friction1) + \
                    (xpar2_vel[0] * ( 1 - friction1)))

                par1.vel[1] = ypar1_vel[1] + ((xpar1_vel[1] * friction1) + \
                    (xpar2_vel[1] * ( 1 - friction1)))

                par1.vel[2] = ypar1_vel[2] + ((xpar1_vel[2] * friction1) + \
                    (xpar2_vel[2] * ( 1 - friction1)))

                par2.vel[0] = ypar2_vel[0] + ((xpar2_vel[0] * friction2) + \
                    (xpar1_vel[0] * ( 1 - friction2)))

                par2.vel[1] = ypar2_vel[1] + ((xpar2_vel[1] * friction2) + \
                    (xpar1_vel[1] * ( 1 - friction2)))

                par2.vel[2] = ypar2_vel[2] + ((xpar2_vel[2] * friction2) + \
                    (xpar1_vel[2] * ( 1 - friction2)))

                if Length > (par.links[i].lenght * (1 + par.links[i].ebroken)) \
                or Length < (par.links[i].lenght  * (1 - par.links[i].broken)):

                    par.links[i].start = -1
                    par.links_activnum -= 1
                    deadlinks[threadid()] += 1

                    parsearch = arraysearch(
                        par2.id,
                        par.link_with,
                        par.link_withnum
                    )

                    if parsearch != -1:
                        par.link_with[parsearch] = -1

                    par2search = arraysearch(
                        par.id,
                        par2.link_with,
                        par2.link_withnum
                    )

                    if par2search != -1:
                        par2.link_with[par2search] = -1

                    # broken_links.append(link)
                    # if par2 in par1.link_with:
                        # par1.link_with.remove(par2)
                    # if par1 in par2.link_with:
                        # par2.link_with.remove(par1)

    # par.links = list(set(par.links) - set(broken_links))
    # free(par1)
    # free(par2)


cdef void update(data):
    global parlist
    global parnum
    global psysnum
    global psys

    cdef int i = 0
    cdef int ii = 0

    for i in range(psysnum):
        psys[i].selfcollision_active = data[i][3]
        
        for ii in range(psys[i].parnum):

            psys[i].particles[ii].loc[0] = data[i][0][(ii * 3)]
            psys[i].particles[ii].loc[1] = data[i][0][(ii * 3) + 1]
            psys[i].particles[ii].loc[2] = data[i][0][(ii * 3) + 2]
            psys[i].particles[ii].vel[0] = data[i][1][(ii * 3)]
            psys[i].particles[ii].vel[1] = data[i][1][(ii * 3) + 1]
            psys[i].particles[ii].vel[2] = data[i][1][(ii * 3) + 2]

            if psys[i].particles[ii].state == 3 and data[i][2][ii] == 3:
                psys[i].particles[ii].state = data[i][2][ii] + 1
                if psys[i].links_active == 1:
                    KDTree_rnn_query(
                        kdtree,
                        &psys[i].particles[ii],
                        psys[i].particles[ii].loc,
                        psys[i].particles[ii].sys.link_length
                    )
                    create_link(psys[i].particles[ii].id, psys[i].link_max)
                    psys[i].particles[ii].neighbours.clear()

            elif psys[i].particles[ii].state == 4 and data[i][2][ii] == 3:
                psys[i].particles[ii].state = 4

            else:
                psys[i].particles[ii].state = data[i][2][ii]

            psys[i].particles[ii].collided_with.clear()


cdef void KDTree_create_nodes(KDTree *kdtree,int parnum)noexcept nogil:
    cdef int i = 0
    i = 2
    while i < parnum:
        i = i * 2
    kdtree.numnodes = i
    kdtree.nodes = <Node *>malloc((kdtree.numnodes + 1) * cython.sizeof(Node))
    kdtree.root_node = <Node *>malloc(1 * cython.sizeof(Node))

    for i in range(kdtree.numnodes):
        kdtree.nodes[i].index = i
        kdtree.nodes[i].name = -1
        kdtree.nodes[i].parent = -1

        kdtree.nodes[i].particle = <SParticle *>malloc(
            1 * cython.sizeof(SParticle)
        )

        kdtree.nodes[i].left_child = <Node *>malloc(1 * cython.sizeof(Node))
        kdtree.nodes[i].right_child = <Node *>malloc(1 * cython.sizeof(Node))
        kdtree.nodes[i].left_child[0].index = -1
        kdtree.nodes[i].right_child[0].index = -1

    kdtree.nodes[kdtree.numnodes].index = -1
    kdtree.nodes[kdtree.numnodes].name = -1
    kdtree.nodes[kdtree.numnodes].parent = -1

    kdtree.nodes[kdtree.numnodes].particle = <SParticle *>malloc(
        1 * cython.sizeof(SParticle)
    )

    kdtree.nodes[kdtree.numnodes].left_child = <Node *>malloc(
        1 * cython.sizeof(Node)
    )

    kdtree.nodes[kdtree.numnodes].right_child = <Node *>malloc(
        1 * cython.sizeof(Node)
    )

    kdtree.nodes[kdtree.numnodes].left_child[0].index = -1
    kdtree.nodes[kdtree.numnodes].right_child[0].index = -1
    kdtree.thread_nodes = <int *>malloc(128 * cython.sizeof(int))
    kdtree.thread_start = <int *>malloc(128 * cython.sizeof(int))
    kdtree.thread_end = <int *>malloc(128 * cython.sizeof(int))
    kdtree.thread_name = <int *>malloc(128 * cython.sizeof(int))
    kdtree.thread_parent = <int *>malloc(128 * cython.sizeof(int))
    kdtree.thread_depth = <int *>malloc(128 * cython.sizeof(int))
    # kdtree.axis = <int *>malloc( 64 * cython.sizeof(int) )

    for i in range(64):
        kdtree.axis[i] = i % 3

    return


cdef Node KDTree_create_tree(
        KDTree *kdtree,
        SParticle *kdparlist,
        int start,
        int end,
        int name,
        int parent,
        int depth,
        int initiate
        )noexcept nogil:

    global parnum

    cdef int index = 0
    cdef int len = (end - start) + 1

    if len <= 0:
        return kdtree.nodes[kdtree.numnodes]

    cdef int axis
    cdef int k = 3
    axis =  kdtree.axis[depth]
    # depth % k
    quick_sort(kdparlist + start, len, axis)

    cdef int median = (start + end) / 2

    if depth == 0:
        kdtree.thread_index = 0
        index = 0
    else:
        index = (parent * 2) + name

    if index > kdtree.numnodes:
        return kdtree.nodes[kdtree.numnodes]

    kdtree.nodes[index].name = name
    kdtree.nodes[index].parent = parent

    if len >= 1 and depth == 0:
        kdtree.root_node[0] = kdtree.nodes[0]

    kdtree.nodes[index].particle[0] = kdparlist[median]

    if parnum > 127:
        if depth == 4 and initiate == 1:
            kdtree.thread_nodes[kdtree.thread_index] = index
            kdtree.thread_start[kdtree.thread_index] = start
            kdtree.thread_end[kdtree.thread_index] = end
            kdtree.thread_name[kdtree.thread_index] = name
            kdtree.thread_parent[kdtree.thread_index] = parent
            kdtree.thread_depth[kdtree.thread_index] = depth
            kdtree.thread_index += 1
            return kdtree.nodes[index]

    kdtree.nodes[index].left_child[0] = KDTree_create_tree(
        kdtree,
        kdparlist,
        start,
        median - 1,
        1,
        index,
        depth + 1,
        initiate
    )
    kdtree.nodes[index].right_child[0] = KDTree_create_tree(
        kdtree,
        kdparlist,
        median + 1,
        end,
        2,
        index,
        depth + 1,
        initiate
    )

    return kdtree.nodes[index]


cdef void KDTree_rnn_query(
        KDTree *kdtree,
        Particle *par,
        float point[3],
        float dist
        )noexcept nogil:
    if  par.state < 3:
        return

    global parlist
    cdef float sqdist  = 0
    cdef int k  = 0
    cdef int i = 0
    par.neighbours.clear()

    if kdtree.root_node[0].index != kdtree.nodes[0].index:
        return
    else:
        sqdist = dist * dist
        KDTree_rnn_search(
            kdtree, &par[0],
            kdtree.root_node[0],
            point,
            dist,
            sqdist,
            3,
            0
        )


#@cython.cdivision(True)
cdef void KDTree_rnn_search(
        KDTree *kdtree,
        Particle *par,
        Node node,
        float point[3],
        float dist,
        float sqdist,
        int k,
        int depth
        )noexcept nogil:

    cdef int axis = 0
    cdef float realsqdist = 0

    if node.index == -1:
        return

    cdef SParticle tparticle = node.particle[0]

    axis = kdtree.axis[depth]

    if (fabs(point[axis] - tparticle.loc[axis])) <= dist:
        realsqdist = square_dist(point, tparticle.loc)

        if realsqdist <= sqdist:
            par.neighbours.push_back(node.particle[0].id)

        KDTree_rnn_search(
            kdtree,
            &par[0],
            node.left_child[0],
            point,
            dist,
            sqdist,
            3,
            depth + 1
        )

        KDTree_rnn_search(
            kdtree,
            &par[0],
            node.right_child[0],
            point,
            dist,
            sqdist,
            3,
            depth + 1
        )

    else:
        if point[axis] <= tparticle.loc[axis]:
            KDTree_rnn_search(
                kdtree,
                &par[0],
                node.left_child[0],
                point,
                dist,
                sqdist,
                3,
                depth + 1
            )

        if point[axis] >= tparticle.loc[axis]:
            KDTree_rnn_search(
                kdtree,
                &par[0],
                node.right_child[0],
                point,
                dist,
                sqdist,
                3,
                depth + 1
            )


cdef void create_link(int par_id, int max_link, int parothers_id=-1)noexcept nogil:
    global kdtree
    global parlist
    global parnum
    global newlinks

    cdef Links *link = <Links *>malloc(1 * cython.sizeof(Links))
    cdef int *neighbours = NULL
    cdef int ii = 0
    cdef int neighboursnum = 0
    cdef float rand_max = 32767
    cdef float relinkrandom = 0
    cdef Particle *par = NULL
    cdef Particle *par2 = NULL
    cdef float stiffrandom = 0
    cdef float damprandom = 0
    cdef float brokrandom = 0
    cdef float tension = 0
    cdef float tensionrandom = 0
    cdef float chancerdom = 0
    cdef Particle *fakepar = NULL
    cdef int create_links
    fakepar = <Particle *>malloc(1 * cython.sizeof(Particle))
    par = &parlist[par_id]

    if  par.state < 3:
        return
    if par.links_activnum >= max_link:
        return
    if par.sys.relink_chance == 0 and par.sys.links_active == 0:
        return

    if parothers_id == -1:
        # KDTree_rnn_query(kdtree, &fakepar[0], par.loc, par.sys.link_length)
        # neighbours = fakepar[0].neighbours
        neighbours = par.neighbours.data()
        neighboursnum = par.neighbours.size()
    else:
        neighbours = <int *>malloc(1 * cython.sizeof(int))
        neighbours[0] = parothers_id
        neighboursnum = 1

    for ii in range(neighboursnum):
        if par.links_activnum >= max_link:
            break
        if parothers_id == -1:
            par2 = &parlist[neighbours[ii]]
            tension = (par.sys.link_tension + par2.sys.link_tension) / 2
        else:
            par2 = &parlist[neighbours[0]]
            tension = (par.sys.link_tension + par2.sys.link_tension) / 2
        if par.id != par2.id:
            # arraysearch(par2.id, par.link_with, par.link_withnum)

            if arraysearch(par.id,par2.link_with,par2.link_withnum) == -1 and \
                    par2.state >= 3 and par.state >= 3:

            #if par not in par2.link_with and par2.state <= 1 \
            #   and par.state <= 1:

                link.start = par.id
                link.end = par2.id

                link.friction = (
                    par.sys.link_friction + par2.sys.link_friction) / 2

                if parothers_id == -1 and par.sys.link_group == par2.sys.link_group:
                    if par.sys.id != par2.sys.id:
                        if par.sys.other_link_active and par2.sys.other_link_active:
                            create_links = 1
                        else:
                            create_links = 0
                    else:
                        create_links = 1

                    if create_links == 1:
                        tensionrandom = (par.sys.link_tensionrand + par2.sys.link_tensionrand) / 2 * 2
                        srand(1)
                        tension = ((par.sys.link_tension + par2.sys.link_tension)/2) * ((((rand() / rand_max) * tensionrandom) - (tensionrandom / 2)) + 1)
                        srand(2)
                        link.lenght = ((sqrtf(square_dist(par.loc,par2.loc)))) * tension
                        stiffrandom = (par.sys.link_stiffrand + par2.sys.link_stiffrand) / 2 * 2
                        link.stiffness = ((par.sys.link_stiff + par2.sys.link_stiff)/2) * ((((rand() / rand_max) * stiffrandom) - (stiffrandom / 2)) + 1)
                        srand(3)
                        link.estiffness = ((par.sys.link_estiff + par2.sys.link_estiff)/2) * ((((rand() / rand_max) * stiffrandom) - (stiffrandom / 2)) + 1)
                        srand(4)
                        link.exponent =  abs(int((par.sys.link_stiffexp + par2.sys.link_stiffexp) / 2))
                        link.eexponent = abs(int((par.sys.link_estiffexp + par2.sys.link_estiffexp) / 2))
                        damprandom = ((par.sys.link_damprand + par2.sys.link_damprand) / 2) * 2
                        link.damping = ((par.sys.link_damp + par2.sys.link_damp) / 2) * ((((rand() / rand_max) * damprandom) - (damprandom / 2)) + 1)
                        srand(5)
                        link.edamping = ((par.sys.link_edamp + par2.sys.link_edamp) / 2) * ((((rand() / rand_max) * damprandom) - (damprandom / 2)) + 1)
                        brokrandom = ((par.sys.link_brokenrand + par2.sys.link_brokenrand) / 2) * 2
                        srand(6)
                        #link.broken = ((par.sys.link_broken + par2.sys.link_broken) / 2) * ((((rand() / rand_max) * brokrandom) - (brokrandom  / 2)) + 1)
                        link.broken = ((par.weak + par2.weak) / 2) * ((par.sys.link_broken + par2.sys.link_broken) / 2) * ((((rand() / rand_max) * brokrandom) - (brokrandom  / 2)) + 1)
                        srand(7)
                        link.ebroken = ((par.weak + par2.weak) / 2) * ((par.sys.link_ebroken + par2.sys.link_ebroken) / 2) * ((((rand() / rand_max) * brokrandom) - (brokrandom  / 2)) + 1)
                        par.links[par.links_num] = link[0]
                        par.links_num += 1
                        par.links_activnum += 1
                        par.links = <Links *>realloc(par.links,(par.links_num + 2) * cython.sizeof(Links))

                        par.link_with[par.link_withnum] = par2.id
                        par.link_withnum += 1

                        par.link_with = <int *>realloc(par.link_with,(par.link_withnum + 2) * cython.sizeof(int))

                        par2.link_with[par2.link_withnum] = par.id
                        par2.link_withnum += 1

                        par2.link_with = <int *>realloc(par2.link_with,(par2.link_withnum + 2) * cython.sizeof(int))
                        newlinks += 1
                        # free(link)

                if parothers_id != -1 and par.sys.relink_group == par2.sys.relink_group:
                    srand(8)
                    relinkrandom = (rand() / rand_max)
                    chancerdom = (par.sys.relink_chancerand + par2.sys.relink_chancerand) / 2 * 2
                    srand(9)

                    if relinkrandom <= ((par.sys.relink_chance + par2.sys.relink_chance) / 2) * ((((rand() / rand_max) * chancerdom) - (chancerdom / 2)) + 1):
                        tensionrandom = (par.sys.relink_tensionrand + par2.sys.relink_tensionrand) / 2 * 2
                        srand(10)
                        tension = ((par.sys.relink_tension + par2.sys.relink_tension)/2) * ((((rand() / rand_max) * tensionrandom) - (tensionrandom / 2)) + 1)
                        srand(11)
                        link.lenght = ((sqrtf(square_dist(par.loc,par2.loc)))) * tension
                        stiffrandom = (par.sys.relink_stiffrand + par2.sys.relink_stiffrand) / 2 * 2
                        link.stiffness = ((par.sys.relink_stiff + par2.sys.relink_stiff)/2) * ((((rand() / rand_max) * stiffrandom) - (stiffrandom / 2)) + 1)
                        srand(12)
                        link.estiffness = ((par.sys.relink_estiff + par2.sys.relink_estiff)/2) * ((((rand() / rand_max) * stiffrandom) - (stiffrandom / 2)) + 1)
                        srand(13)
                        link.exponent = abs(int((par.sys.relink_stiffexp + par2.sys.relink_stiffexp) / 2))
                        link.eexponent = abs(int((par.sys.relink_estiffexp + par2.sys.relink_estiffexp) / 2))
                        damprandom = ((par.sys.relink_damprand + par2.sys.relink_damprand) / 2) * 2
                        link.damping = ((par.sys.relink_damp + par2.sys.relink_damp) / 2) * ((((rand() / rand_max) * damprandom) - (damprandom / 2)) + 1)
                        srand(14)
                        link.edamping = ((par.sys.relink_edamp + par2.sys.relink_edamp) / 2) * ((((rand() / rand_max) * damprandom) - (damprandom / 2)) + 1)
                        brokrandom = ((par.sys.relink_brokenrand + par2.sys.relink_brokenrand) / 2) * 2
                        link.broken = ((par.sys.relink_broken + par2.sys.relink_broken) / 2) * ((((rand() / rand_max) * brokrandom) - (brokrandom  / 2)) + 1)
                        srand(15)
                        link.ebroken = ((par.sys.relink_ebroken + par2.sys.relink_ebroken) / 2) * ((((rand() / rand_max) * brokrandom) - (brokrandom  / 2)) + 1)
                        par.links[par.links_num] = link[0]
                        par.links_num += 1
                        par.links_activnum += 1
                        par.links = <Links *>realloc(par.links,(par.links_num + 1) * cython.sizeof(Links))
                        par.link_with[par.link_withnum] = par2.id
                        par.link_withnum += 1
                        par.link_with = <int *>realloc(par.link_with,(par.link_withnum + 1) * cython.sizeof(int))
                        par2.link_with[par2.link_withnum] = par.id
                        par2.link_withnum += 1
                        par2.link_with = <int *>realloc(par2.link_with,(par2.link_withnum + 1) * cython.sizeof(int))
                        newlinks += 1
                        # free(link)
    # free(neighbours)
    free(fakepar)
    free(link)
    # free(par)
    # free(par2)


cdef struct Pool:
    int axis
    float offset
    float max
    Parity *parity


cdef struct Parity:
    Heap *heap


cdef struct Heap:
    int *par
    int parnum
    int maxalloc


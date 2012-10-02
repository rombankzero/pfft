//          Copyright Jernej Krempuš 2012
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

module pfft.shuffle;

import core.bitop;

template st(alias a){ enum st = cast(size_t) a; }

struct Tuple(A...)
{
    A a;
    alias a this;
}

void _swap(T)(ref T a, ref T b)
{
    auto aa = a;
    auto bb = b;
    b = aa;
    a = bb;
}

template ints_up_to(int n, T...)
{
    static if(n)
    {
        alias ints_up_to!(n-1, n-1, T) ints_up_to;
    }
    else
        alias T ints_up_to;
}

template powers_up_to(int n, T...)
{
    static if(n > 1)
    {
        alias powers_up_to!(n / 2, n / 2, T) powers_up_to;
    }
    else
        alias T powers_up_to;
}

template RepeatType(T, int n, R...)
{
    static if(n == 0)
        alias R RepeatType;
    else
        alias RepeatType!(T, n - 1, T, R) RepeatType;
}

struct BitReversedPairs
{
    int mask;
    uint i1;
    uint i2;

    @property front(){ return Tuple!(uint, uint)(i1, i2); }

    void popFront()
    {
        i2 = mask ^ (i2 ^ (mask>>(bsf(i1)+1)));
        --i1;
    }

    @property empty(){ return i1 == 0u - 1u; } 
}
    
auto bit_reversed_pairs(int log2n)
{
    int mask = (0xffffffff<<(log2n));
    uint i2 = ~mask; 
    uint i1 = i2;

    return BitReversedPairs(mask, i1, i2);
}

void bit_reverse_simple(T)(T* p, int log2n)
{
    foreach(i0, i1; bit_reversed_pairs(log2n))
        if(i1 > i0)
            _swap(p[i0],p[i1]);
}

template reverse_bits(int i, int bits_left, int r = 0)
{
    static if(bits_left == 0)
        enum reverse_bits = r;
    else
        enum reverse_bits = reverse_bits!(
            i >> 1, bits_left - 1, (r << 1) | (i & 1));
}

auto bit_reverse_static_size(int log2n, T, S...)(T* p, S stride) 
    if(S.length <= 1) 
{
    enum n = 1 << log2n;
    enum l = 1 << (log2n / 2);   
    
    static if(stride.length == 1)
        auto index(size_t i)(S s){ return i / l * s[0] + i % l; } 
    else
        auto index(size_t i)(S s){ return i; }

    RepeatType!(T, n) a;
    
    foreach(i, _; a)
        static if(i != reverse_bits!(i, log2n)) 
            a[i] = p[index!i(stride)];
    
    foreach(i, _; a)
        static if(i != reverse_bits!(i, log2n)) 
            p[index!i(stride)] = a[reverse_bits!(i, log2n)];
}

auto bit_reverse_tiny(int max_log2n, T)(T* p, int log2n)
{
    switch(log2n)
    {
        foreach(i; ints_up_to!max_log2n)
        {
            case i:
                bit_reverse_static_size!i(p);
                break;
        }
        
        default:
    }
}

void bit_reverse_step(size_t chunk_size, T)(T* p, size_t nchunks)
{
    for(size_t i = chunk_size, j = (nchunks >> 1) * chunk_size; 
        j < nchunks * chunk_size; 
        j += chunk_size*2, i += chunk_size*2)
    {        
        foreach(k; ints_up_to!chunk_size)
            _swap(p[i + k], p[j + k]);
    }
}

struct BitReverse(alias V, Options)
{
    alias V.T T;
    alias V.vec vec;
    
    static size_t br_table_size()(int log2n)
    {
        enum log2l = V.log2_bitreverse_chunk_size;
 
        return log2n < log2l * 2 ? 0 : (1 << (log2n - 2 * log2l)) + 2 * log2l;
    }
    
    static void init_br_table()(uint* table, int log2n)
    {
        enum log2l = V.log2_bitreverse_chunk_size;

        foreach(i; bit_reversed_pairs(log2n - 2 * log2l))
            if(i[1] == i[0])
            {
                *table = i[0] << log2l;
                table++;
            }

        foreach(i; bit_reversed_pairs(log2n - 2 * log2l))
            if(i[1] < i[0])
            {
                *table = i[0] << log2l;
                table++;
                *table = i[1] << log2l;
                table++;
            }
    }
       
    static void bit_reverse_small()(T*  p, uint log2n, uint*  table)
    {
        enum log2l = V.log2_bitreverse_chunk_size;
        
        uint tmp = log2n - log2l - log2l;
        uint n1 = 1u << ((tmp + 1) >> 1);
        uint n2 = 1u << tmp;
        uint m = 1u << (log2n - log2l);
      
        uint* t1 = table + n1, t2 = table + n2;
      
        for(; table < t1; table++)
            V.bit_reverse( p + table[0], m);
        for(; table < t2; table += 2)
            V.bit_reverse_swap( p + table[0], p + table[1], m);
    }

    private static auto highest_power_2(int a, int maxpower)
    {
        while(a % maxpower)
            maxpower /= 2;

        return maxpower;     
    }

    static void swap_some(int n, TT)(TT* a, TT* b)
    {
        RepeatType!(TT, 2 * n) tmp;
        
        foreach(i; ints_up_to!n)
            tmp[i] = a[i];
        foreach(i; ints_up_to!n)
            tmp[i + n] = b[i];
        
        foreach(i; ints_up_to!n)
            b[i] = tmp[i];
        foreach(i; ints_up_to!n)
            a[i] = tmp[i + n];
    }

    static void swap_array(int len, TT)(TT *  a, TT *  b)
    {
        static assert(len*TT.sizeof % vec.sizeof == 0);
        
        enum n = highest_power_2( len * TT.sizeof / vec.sizeof, 4);
        
        foreach(i; 0 .. len * TT.sizeof / n / vec.sizeof)
            swap_some!n((cast(vec*)a) + n * i, (cast(vec*)b) + n * i);
    }
    
    static void copy_some(int n, TT)(TT* dst, TT* src)
    {
        RepeatType!(TT, n) a;
        
        foreach(i, _; a)
            a[i] = src[i];
        foreach(i, _; a)
            dst[i] = a[i];
    }
    
    static void copy_array(int len, TT)(TT *  a, TT *  b)
    {
        static assert((len * TT.sizeof % vec.sizeof == 0));
        
        enum n = highest_power_2( len * TT.sizeof / vec.sizeof, 8);

        foreach(i; 0 .. len * TT.sizeof / n / vec.sizeof)
            copy_some!n((cast(vec*)a) + n * i, (cast(vec*)b) + n * i);
    }
    
    static void strided_copy(size_t chunk_size, TT)(
        TT* dst, TT* src, size_t dst_stride, size_t src_stride, size_t nchunks)
    {
        for(
            TT* s = src, d = dst; 
            s < src + nchunks * src_stride; 
            s += src_stride, d += dst_stride)
        {
            copy_array!chunk_size(d, s);
        }
    } 

    static void bit_reverse_large()(
        T* p, int log2n, uint * table, void* tmp_buffer)
    {
        enum log2l = Options.log2_bitreverse_large_chunk_size;
        enum l = 1<<log2l;
        
        auto buffer = cast(T*) tmp_buffer;
        
        int log2m = log2n - log2l;
        size_t m = 1<<log2m, n = 1<<log2n;
        T * pend = p + n;
       
        foreach(i; bit_reversed_pairs(log2m - log2l))
            if(i[1] >= i[0])
            {
                strided_copy!l(buffer, p + i[0] * l, l, m, l);
          
                bit_reverse_small(buffer,log2l+log2l, table);

                if(i[1] != i[0])
                {
                    for(
                        T* pp = p + i[1] * l, pb = buffer;
                        pp < pend; 
                        pb += l, pp += m)
                    {
                        swap_array!l(pp, pb);
                    }
                
                    bit_reverse_small(buffer,log2l+log2l, table);
                }

                strided_copy!l(p + i[0] * l, buffer, m, l, l);
            }
    }
}

private struct Scalar(TT)
{
    public:

    alias TT T;
    alias TT vec;
    enum vec_size = 1;
    
    static void interleave(vec a0, vec a1, ref vec r0, ref vec r1)
    {
        r0 = a0;
        r1 = a1; 
    }
    
    static void deinterleave(vec a0, vec a1, ref vec r0, ref vec r1)
    {
        r0 = a0;
        r1 = a1; 
    }
}

template hasInterleaving(V)
{
    enum hasInterleaving =  
        is(typeof(V.interleave)) && 
        is(typeof(V.deinterleave));
}

struct InterleaveImpl(V, int chunk_size, bool is_inverse, bool swap_even_odd) 
{
    static size_t itable_size_bytes()(int log2n)
    {
        return (bool.sizeof << log2n) / V.vec_size / chunk_size; 
    }

    static bool* interleave_table()(int log2n, void* p)
    {
        auto n = st!1 << log2n;
        auto is_cycle_minimum = cast(bool*) p;
        size_t n_chunks = n / V.vec_size / chunk_size;

        if(n_chunks < 4)
            return null;

        is_cycle_minimum[0 .. n_chunks] = true;    

        for(size_t i = 1;;)
        {
            size_t j = i;
            while(true)
            {
                j = j < n_chunks / 2 ? 2 * j : 2 * (j - n_chunks / 2) + 1;
                if(j == i)
                    break;

                is_cycle_minimum[j] = false;
            }

            // The last cycle minimum is at n / 2 - 1
            if(i == n_chunks / 2 - 1)
                break;           

            do i++; while(!is_cycle_minimum[i]);
        }

        return is_cycle_minimum;
    }

    static void interleave_chunks()(
        V.vec* a, size_t n_chunks, bool* is_cycle_minimum)
    {
        alias RepeatType!(V.vec, chunk_size) RT;
        alias ints_up_to!chunk_size indices;        

        for(size_t i = 1;;)
        {
            size_t j = i;

            RT element;
            auto p = &a[i * chunk_size];
            foreach(k; indices)
                element[k] = p[k];

            while(true)
            {
                static if(is_inverse)
                    j = j & 1 ? j / 2 + n_chunks / 2 : j / 2;
                else
                    j = j < n_chunks / 2 ? 2 * j : 2 * (j - n_chunks / 2) + 1;
                
                if(j == i)
                    break;

                RT tmp;
                p = &a[j * chunk_size];
                foreach(k; indices)
                    tmp[k] = p[k];

                foreach(k; indices)
                    p[k] = element[k];

                foreach(k; indices)
                    element[k] = tmp[k];
            }

            p = &a[i * chunk_size];
            foreach(k; indices)
                p[k] = element[k];

            if(i == n_chunks / 2 - 1)
                break;           

            do i++; while(!is_cycle_minimum[i]);
        }
    }

    static void interleave_static_size(int n)(V.vec* p)
    {
        RepeatType!(V.vec, 2 * n) tmp;

        enum even = swap_even_odd ? n : 0;
        enum odd = swap_even_odd ? 0 : n;

        static if(is_inverse)
            foreach(j; ints_up_to!n)
                V.deinterleave(
                    p[2 * j], p[2 * j + 1], tmp[even + j], tmp[odd + j]);
        else
            foreach(j; ints_up_to!n)
                V.interleave(
                    p[even + j], p[odd + j], tmp[2 * j], tmp[2 * j + 1]);

        foreach(j; ints_up_to!(2 * n))
            p[j] = tmp[j];

    }

    static void interleave_tiny()(V.vec* p, size_t len)
    {
        switch(len)
        {
            foreach(n; powers_up_to!(2 * chunk_size))
            {
                case 2 * n:
                    interleave_static_size!n(p); 
                    break;
            }

            default: {}
        }
    }

    static void interleave_chunk_elements()(V.vec* a, size_t n_chunks)
    {
        for(auto p = a; p < a + n_chunks * chunk_size; p += 2 * chunk_size)
            interleave_static_size!chunk_size(p);
    }

    static void interleave()(V.T* p, int log2n, bool* table)
    {
        auto n = st!1 << log2n;

        if(n < 4)
            return;
        else if(n < 2 * V.vec_size)
            return 
                InterleaveImpl!(
                    Scalar!(V.T), V.vec_size / 2, is_inverse, swap_even_odd)
                    .interleave_tiny(p, n);

        assert(n >= 2 * V.vec_size);
       
        auto vp = cast(V.vec*) p;
        auto vn = n / V.vec_size;
 
        if(n < 4 * V.vec_size * chunk_size)
            interleave_tiny(vp, vn);
        else
        {
            auto n_chunks = vn / chunk_size;
            static if(is_inverse)
            {
                interleave_chunk_elements(vp, n_chunks);
                interleave_chunks(vp, n_chunks, table);
            }
            else
            {
                interleave_chunks(vp, n_chunks, table);
                interleave_chunk_elements(vp, n_chunks);
            }
        }  
    }
}

template Interleave(
    V, int chunk_size, bool is_inverse, bool swap_even_odd = false)
{
    static if(hasInterleaving!V)
        alias InterleaveImpl!(V, chunk_size, is_inverse, swap_even_odd) 
            Interleave;
    else
        alias 
            InterleaveImpl!(Scalar!(V.T), chunk_size, is_inverse, swap_even_odd) 
            Interleave;
}

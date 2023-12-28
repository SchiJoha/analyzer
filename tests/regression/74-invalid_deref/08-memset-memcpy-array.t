  $ goblint --set ana.activated[+] memOutOfBounds --enable ana.int.interval 08-memset-memcpy-array.c
  Option warning: The memOutOfBounds analysis enables cil.addNestedScopeAttr.
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void *)b in function memset is 168 (in bytes) with an address offset of 0 (in bytes). Count is 169 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:14:5-14:22)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void *)b in function memset is 168 (in bytes) with an address offset of 0 (in bytes). Count is 169 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:15:5-15:34)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void const   * __restrict  )c in function memcpy is 168 (in bytes) with an address offset of 0 (in bytes). Count is 169 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:20:5-20:22)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void * __restrict  )b in function memcpy is 168 (in bytes) with an address offset of 0 (in bytes). Count is 169 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:20:5-20:22)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void const   * __restrict  )c in function memcpy is 168 (in bytes) with an address offset of 0 (in bytes). Count is 169 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:21:5-21:34)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void * __restrict  )b in function memcpy is 168 (in bytes) with an address offset of 0 (in bytes). Count is 169 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:21:5-21:34)
  [Warning][Unknown] Pointer argv has a points-to-set of top. An invalid memory access might occur (08-memset-memcpy-array.c:25:9-25:20)
  [Warning][Unknown] Size of lval dereference expression argv is top. Out-of-bounds memory access may occur (08-memset-memcpy-array.c:25:9-25:20)
  [Warning][Behavior > Undefined > Other] Pointer argv contains an unknown address. Invalid dereference may occur (08-memset-memcpy-array.c:25:9-25:20)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of pointer argv is top. Memory out-of-bounds access might occur due to pointer arithmetic (08-memset-memcpy-array.c:25:9-25:20)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void *)b in function memset is 4 (in bytes) with an address offset of 0 (in bytes). Count is 168 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:27:9-27:26)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void * __restrict  )b in function memcpy is 4 (in bytes) with an address offset of 0 (in bytes). Count is 168 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:28:9-28:26)
  [Warning][Unknown] Pointer argv + 5 has a points-to-set of top. An invalid memory access might occur (08-memset-memcpy-array.c:29:16-29:27)
  [Warning][Unknown] Size of lval dereference expression argv + 5 is top. Out-of-bounds memory access may occur (08-memset-memcpy-array.c:29:16-29:27)
  [Warning][Behavior > Undefined > Other] Pointer argv contains an unknown address. Invalid dereference may occur (08-memset-memcpy-array.c:29:16-29:27)
  [Warning][Unknown] Pointer argv has a points-to-set of top. An invalid memory access might occur (08-memset-memcpy-array.c:29:16-29:27)
  [Warning][Integer > Overflow][CWE-190] Signed integer overflow (08-memset-memcpy-array.c:29:16-29:27)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of pointer argv in expression argv + 5 is top. Memory out-of-bounds access might occur (08-memset-memcpy-array.c:29:16-29:27)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void *)b in function memset is 4 (in bytes) with an address offset of 0 (in bytes). Count is 168 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:32:9-32:26)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Size of (void * __restrict  )b in function memcpy is 4 (in bytes) with an address offset of 0 (in bytes). Count is 168 (in bytes). Memory out-of-bounds access must occur (08-memset-memcpy-array.c:33:9-33:26)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Could not compare size of dest ((Not {0}([0,8]),[4,168]) with address offset (0) count (168) in function memset. Memory out-of-bounds access may occur (08-memset-memcpy-array.c:36:5-36:30)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Could not compare size of dest ((Not {0}([0,8]),[4,168]) with address offset (0) count (168) in function memcpy. Memory out-of-bounds access may occur (08-memset-memcpy-array.c:37:5-37:30)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Could not compare size of dest ((Not {0}([0,8]),[4,168]) with address offset (0) count (5) in function memset. Memory out-of-bounds access may occur (08-memset-memcpy-array.c:40:5-40:34)
  [Warning][Behavior > Undefined > MemoryOutOfBoundsAccess][CWE-823] Could not compare size of dest ((Not {0}([0,8]),[4,168]) with address offset (0) count (5) in function memcpy. Memory out-of-bounds access may occur (08-memset-memcpy-array.c:41:5-41:34)
  [Info][Deadcode] Logical lines of code (LLoC) summary:
    live: 27
    dead: 0
    total lines: 27

/*
 * *No header guard*: the header is allowed to be included twice
 * with different sets of defines.
 */
/*
 * Copyright 2010-2016, Tarantool AUTHORS, please see AUTHORS file.
 *
 * Redistribution and use in source and binary forms, with or
 * without modification, are permitted provided that the following
 * conditions are met:
 *
 * 1. Redistributions of source code must retain the above
 *		copyright notice, this list of conditions and the
 *		following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above
 *		copyright notice, this list of conditions and the following
 *		disclaimer in the documentation and/or other materials
 *		provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY <COPYRIGHT HOLDER> ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED
 * TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL
 * <COPYRIGHT HOLDER> OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 * INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR
 * BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF
 * LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF
 * THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#include <stddef.h>
#include <stdint.h>
#include <stdbool.h>
#include <assert.h>
#include <memory.h>

/**
 * Additional user defined name that appended to prefix 'heap'
 *	for all names of structs and functions in this header file.
 * All names use pattern: heap<HEAP_NAME>_<name of func/struct>
 * May be empty, but still have to be defined (just #define HEAP_NAME)
 * Example:
 * #define HEAP_NAME _test
 * ...
 * struct heap_test_core some_heap;
 * heap_test_init(&some_heap, ...);
 */
#ifndef HEAP_NAME
#error "HEAP_NAME must be defined"
#endif

/**
 * Data comparing function. Takes 3 parameters - heap, node1, node2,
 * where heap is pointer onto core structure and node1, node2
 * are two pointers on nodes in your structure.
 * For example you have such type:
 *	 struct my_type {
 *	 	int value;
 *	 	struct heap_<HEAP_NAME>_node vnode;
 *	 };
 * Then node1 and node2 will be pointers on field vnode of two
 * my_type instances.
 * The function below is example of valid comparator by value:
 *
 * int test_type_less(const struct heap_<HEAP_NAME>_core *heap,
 *			const struct heap_<HEAP_NAME>_node *a,
 *			const struct heap_<HEAP_NAME>_node *b) {
 *
 *	const struct my_type *left = (struct my_type *)((char *)a -
 *					offsetof(struct my_type, vnode));
 *	const struct my_type *right = (struct my_type *)((char *)b -
 *					offsetof(struct my_type, vnode));
 *	return left->value < right->value;
 * }
 *
 * HEAP_LESS is less function that is important!
 */
#ifndef HEAP_LESS
#error "HEAP_LESS must be defined"
#endif

/**
 * Tools for name substitution:
 */
#ifndef CONCAT4
#define CONCAT4_R(a, b, c, d) a##b##c##d
#define CONCAT4(a, b, c, d) CONCAT4_R(a, b, c, d)
#endif

#ifdef _
#error '_' must be undefinded!
#endif
#ifndef HEAP
#define HEAP(name) CONCAT4(heap, HEAP_NAME, _, name)
#endif

/* Structures. */

/**
 * Main structure for holding heap.
 */
struct HEAP(core) {
	size_t size;
	struct HEAP(node) *root; /* pointer onto root of the heap */
};

/**
 * Heap entry structure.
 */
struct HEAP(node) {
	struct HEAP(node) *neighbours[3];
	/*
	0 - left child
	1 - right child
	2 - parent
	*/
};

/**
 * Heap iterator structure.
 */
struct HEAP(iterator) {
	struct HEAP(node) *current_node;
	int depth; // current depth in tree
	uint64_t mask; // mask of left/right choices
};


/* Extern API that is the most usefull part. */

/**
 * Init heap.
 */
 static inline void
 HEAP(init)(struct HEAP(core) *heap);

/**
 * Returns root node of heap.
 */
static inline struct HEAP(node) *
HEAP(get_root)(struct HEAP(node) *node);

/**
 * Erase min value.
 */
static inline struct HEAP(node) *
HEAP(pop)(struct HEAP(core) *heap);

/**
 * Insert value.
 */
static inline void
HEAP(insert)(struct HEAP(core) *heap, struct HEAP(node) *nd);

/**
 * Delete node from heap.
 */
static inline void
HEAP(delete)(struct HEAP(core) *heap, struct HEAP(node) *value_node);

/**
 * Heapify tree after update of value under value_node pointer.
 */
static inline void
HEAP(update)(struct HEAP(core) *heap, struct HEAP(node) *value_node);

/**
 * Heap iterator init.
 */
static inline void
HEAP(iterator_init)(struct HEAP(core) *heap, struct HEAP(iterator) *it);

/**
 * Heap iterator next.
 */
static inline struct HEAP(node) *
HEAP(iterator_next) (struct HEAP(iterator) *it);

/**
 * Debug functions. They are usually useless,
 * but aplicable for testing.
 */

/**
 * Debug function. Check heap invariants for pair node, parent.
 */
static inline bool
HEAP(check_local_invariants) (struct HEAP(core) *heap,
			      struct HEAP(node) *node,
			      struct HEAP(node) *parent);

/*
 * Debug function. Check heap invariants for all nodes.
 */
static inline bool
HEAP(check_invariants)(struct HEAP(core) *heap,
		       struct HEAP(node) *node,
		       struct HEAP(node) *parent);


/* Routines. Functions below are useless for ordinary user. */

/**
 * Init heap node.
 */
static inline void
HEAP(init_node)(struct HEAP(node) *node);

/**
 * Swap two parent and son.
 */
static inline void
HEAP(swap_parent_and_son)(struct HEAP(core) *heap,
			  struct HEAP(node) *parent,
			  struct HEAP(node) *son);

/**
 * Update parent field of children.
 */
static inline void
HEAP(push_info_to_children)(struct HEAP(node) *node);

/**
 * Update left or right field of parent.
 */
static inline void
HEAP(push_info_to_parent)(struct HEAP(node) *parent, struct HEAP(node) *son);

/**
 * Cut leaf. Node is a pointer to leaf.
 */
static void
HEAP(cut_leaf)(struct HEAP(node) *node);

/**
 * Get first not full, i.e. first node with less that 2 sons.
 */
static struct HEAP(node)*
HEAP(get_first_not_full)(struct HEAP(core) *heap);

/**
 * Get last node, i.e. the most right in bottom layer.
 */
static struct HEAP(node) *
HEAP(get_last)(struct HEAP(core) *heap);

/**
 * Sift up current node.
 */
static void
HEAP(sift_up)(struct HEAP(core) *heap, struct HEAP(node) *node);

/**
 * Sift down current node.
 */
static void
HEAP(sift_down)(struct HEAP(core) *heap, struct HEAP(node) *node);

/* Function defenitions */

/**
 * Init heap node.
 */
static inline void
HEAP(init_node)(struct HEAP(node) *node)
{
	memset((void*) node->neighbours, 0, sizeof(struct HEAP(node) *) * 3);
}

/**
 * Init heap.
 */
static inline void
HEAP(init)(struct HEAP(core) *heap)
{
	heap->size = 0;
	heap->root = NULL;
}

/**
 * Returns root node of heap.
 */
static inline struct HEAP(node) *
HEAP(get_root)(struct HEAP(node) *node)
{
	while (node->neighbours[2]) {
		node = node->neighbours[2];
	}

	return node;
}

/**
 * Update parent field of children.
 */
static inline void
HEAP(push_info_to_children)(struct HEAP(node) *node)
{
	if (node->neighbours[0])
		node->neighbours[0]->neighbours[2] = node;

	if (node->neighbours[1])
		node->neighbours[1]->neighbours[2] = node;

}

/**
 * Update left or right field of parent.
 */
static inline void
HEAP(push_info_to_parent)(struct HEAP(node) *parent, struct HEAP(node) *son)
{
	assert(parent);
	assert(son);
	if (!parent->neighbours[2])
		return;
	struct HEAP(node) *pparent = parent->neighbours[2];
	pparent->neighbours[pparent->neighbours[0] != son] = parent;
}

/**
 * Cut leaf. Node is a pointer to leaf.
 */
static inline void
HEAP(cut_leaf)(struct HEAP(node) *node)
{
	assert(node);
	assert(node->neighbours[0] == NULL);
	assert(node->neighbours[1] == NULL);

	if (node->neighbours[2] == NULL)
		return;

	struct HEAP(node) *parent = node->neighbours[2];
	parent->neighbours[parent->neighbours[1] == node] = NULL;
	return;
}

/**
 * Swap two connected(i.e parent and son) nodes.
 */
static inline void
HEAP(swap_parent_and_son)(struct HEAP(core) *heap,
			  struct HEAP(node) *parent,
			  struct HEAP(node) *son)
{
	assert(parent && son && son->neighbours[2] == parent);
	struct HEAP(node) tmp = *parent;
	*parent = *son;
	*son = tmp;

	son->neighbours[son->neighbours[0] != son] = parent;

	HEAP(push_info_to_children)(parent);
	HEAP(push_info_to_children)(son);
	HEAP(push_info_to_parent)(son, parent);

	if (son->neighbours[2] == NULL)
		heap->root = son; /* save root */
}

/**
 * Get first not full, i.e. first node with less that 2 sons.
 */
static struct HEAP(node) *
HEAP(get_first_not_full)(struct HEAP(core) *heap)
{
	struct HEAP(node) *node = heap->root;
	uint64_t mask = heap->size + 1;
	struct HEAP(node) *root = heap->root;

	int shift = 62 - __builtin_clzll(mask);
	for (uint64_t bit = 1ull << shift; bit > 1ull; bit >>= 1)
		root = root->neighbours[(mask & bit) != 0];

	return root;
}

/**
 * Get last node, i.e. the most right in bottom layer.
 */
static struct HEAP(node) *
HEAP(get_last)(struct HEAP(core) *heap)
{
	uint64_t mask = heap->size;

	if (mask == 1)
		return heap->root;

	int shift = 62 - __builtin_clzll(mask);
	struct HEAP(node) *root = heap->root;
	uint64_t subtree_size;
	for (uint64_t bit = 1ull << shift; bit > 0; bit >>= 1)
		root = root->neighbours[(mask & bit) != 0];

	return root;
}


/**
 * Sift up current node.
 */
static void
HEAP(sift_up)(struct HEAP(core) *heap, struct HEAP(node) *node)
{
	(void) heap;
	assert(node);
	struct HEAP(node) *parent = node->neighbours[2];
	while (parent && HEAP_LESS(heap, node, parent)) {
		HEAP(swap_parent_and_son)(heap, parent, node);
		parent = node->neighbours[2];
	}
}

/**
 * Sift down current node.
 */
static void
HEAP(sift_down)(struct HEAP(core) *heap, struct HEAP(node) *node)
{
	(void) heap;
	assert(node);
	struct HEAP(node) *left = node->neighbours[0];
	struct HEAP(node) *right = node->neighbours[1];
	struct HEAP(node) *min_son;
	if (left && right)
		min_son = (HEAP_LESS(heap, left, right) ? left : right);

	while (left && right && HEAP_LESS(heap, min_son, node)) {
		HEAP(swap_parent_and_son)(heap, node, min_son);
		left = node->neighbours[0];
		right = node->neighbours[1];

		if (left && right)
			min_son = (HEAP_LESS(heap, left, right) ? left : right);
	}

	if ((left || right) && HEAP_LESS(heap, left, node)) {
		assert(left); /*left is not null because heap is complete tree*/
		assert(right == NULL);
		if (HEAP_LESS(heap, left, node))
			HEAP(swap_parent_and_son)(heap, node, left);
	}
}

/**
 * Insert value.
 */
static inline void
HEAP(insert)(struct HEAP(core) *heap, struct HEAP(node) *node)
{
	(void) heap;
	assert(heap);

	if (node == NULL)
		return;

	HEAP(init_node)(node);
	if (heap->root == NULL) {
		/* save new root */
		heap->root = node;
		heap->size = 1;
		return;
	}

	struct HEAP(node) *first_not_full = HEAP(get_first_not_full)(heap);
	node->neighbours[2] = first_not_full;
	first_not_full->neighbours[first_not_full->neighbours[0] != NULL] = node;

	heap->size++;

	HEAP(sift_up)(heap, node); /* heapify */

}

/**
 * Erase min value. Returns delete value.
 */
static inline struct HEAP(node) *
HEAP(pop)(struct HEAP(core) *heap)
{
	(void) heap;
	assert(heap);
	struct HEAP(node) *res = heap->root;
	HEAP(delete)(heap, heap->root);
	return res;
}

/*
 * Delete node from heap.
 */
static inline void
HEAP(delete)(struct HEAP(core) *heap, struct HEAP(node) *value_node)
{
	(void) heap;
	assert(heap);
	struct HEAP(node) *root = heap->root;
	struct HEAP(node) *last_node = HEAP(get_last)(heap);

	/* check that we try make heap empty */
	if (last_node == root) {
		assert(last_node == value_node);
		/* save new root */
		heap->root = NULL;
		heap->size = 0;
		return;
	}

	assert(last_node->neighbours[0] == NULL);
	assert(last_node->neighbours[1] == NULL);

	heap->size--;
	/* cut leaf */
	HEAP(cut_leaf)(last_node);

	/* check that we try to delete last node */
	if (value_node == last_node) {
		return;
	}

	/* insert last_node as root */
	*last_node = *value_node;
	if (last_node->neighbours[2] == NULL)
		heap->root = last_node; /* save root */

	HEAP(push_info_to_parent)(last_node, value_node);
	HEAP(push_info_to_children)(last_node);

	/* delete root from tree */
	memset((void*) value_node->neighbours, 0, sizeof(struct HEAP(node) *) * 3);

	/*heapify */
	HEAP(update)(heap, last_node);
}

/**
 * Heapify tree after update of value under value_node pointer.
 */
static inline void
HEAP(update)(struct HEAP(core) *heap, struct HEAP(node) *value_node)
{
	(void) heap;
	assert(heap);
	/* heapify */
	HEAP(sift_down)(heap, value_node);
	HEAP(sift_up)(heap, value_node);
}


/**
 * Debug function. Check heap invariants for pair node, parent.
 */
static inline bool
HEAP(check_local_invariants)(struct HEAP(core) *heap,
			     struct HEAP(node) *parent,
			     struct HEAP(node) *node)
{
	(void) heap;
	assert(node);

	if (parent != node->neighbours[2])
		return false;
	if (parent && parent->neighbours[0] != node && parent->neighbours[1] != node)
		return false;

	if (node->neighbours[0] && HEAP_LESS(heap, node->neighbours[0], node))
		return false;

	if (node->neighbours[1] && HEAP_LESS(heap, node->neighbours[0], node))
		return false;

	return true;
}

/**
 * Debug function. Check heap invariants for all nodes.
 */
static inline bool
HEAP(check_invariants)(struct HEAP(core) *heap,
		       struct HEAP(node) *parent,
		       struct HEAP(node) *node)
{
	(void) heap;
	if (!node)
		return true;

	if (!HEAP(check_local_invariants)(heap, parent, node))
		return false;

	bool check_left = HEAP(check_invariants)(heap, node, node->neighbours[0]);
	bool check_right = HEAP(check_invariants)(heap, node, node->neighbours[1]);

	return (check_right && check_left);
}

/**
 * Heap iterator init.
 */
static inline void
HEAP(iterator_init)(struct HEAP(core) *heap, struct HEAP(iterator) *it)
{
	(void) heap;
	it->current_node = heap->root;
	it->mask = 0;
	it->depth = 0;
}

/**
 * Heap iterator next.
 */
static inline struct HEAP(node) *
HEAP(iterator_next)(struct HEAP(iterator) *it)
{
	struct HEAP(node) *cnode = it->current_node;

	if (!cnode)
		return NULL;

	if (cnode && cnode->neighbours[0]) {
		it->mask = it->mask & (~ (1 << it->depth));
		it->depth++;
		it->current_node = cnode->neighbours[0];
		return cnode;
	}

	while (((it->mask & (1 << it->depth)) ||
			it->current_node->neighbours[1] == NULL) &&
			it->depth) {
		it->depth--;
		it->current_node = it->current_node->neighbours[2];
	}

	if (it->depth == 0 && (it->mask & 1 || it->current_node == NULL)) {
		it->current_node = NULL;
		return cnode;
	}

	it->current_node = it->current_node->neighbours[2];
	it->mask = it->mask | (1 << it->depth);
	it->depth++;

	return cnode;
}

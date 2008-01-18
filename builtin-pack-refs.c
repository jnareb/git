#include "builtin.h"
#include "cache.h"
#include "refs.h"
#include "object.h"
#include "tag.h"
#include "parse-options.h"

struct ref_to_prune {
	struct ref_to_prune *next;
	unsigned char sha1[20];
	char name[FLEX_ARRAY];
};

#define PACK_REFS_PRUNE	0x0001
#define PACK_REFS_ALL	0x0002

struct pack_refs_cb_data {
	unsigned int flags;
	struct ref_to_prune *ref_to_prune;
	FILE *refs_file;
};

static int do_not_prune(int flags)
{
	/* If it is already packed or if it is a symref,
	 * do not prune it.
	 */
	return (flags & (REF_ISSYMREF|REF_ISPACKED));
}

static int handle_one_ref(const char *path, const unsigned char *sha1,
			  int flags, void *cb_data)
{
	struct pack_refs_cb_data *cb = cb_data;
	int is_tag_ref;

	/* Do not pack the symbolic refs */
	if ((flags & REF_ISSYMREF))
		return 0;
	is_tag_ref = !prefixcmp(path, "refs/tags/");

	/* ALWAYS pack refs that were already packed or are tags */
	if (!(cb->flags & PACK_REFS_ALL) && !is_tag_ref && !(flags & REF_ISPACKED))
		return 0;

	fprintf(cb->refs_file, "%s %s\n", sha1_to_hex(sha1), path);
	if (is_tag_ref) {
		struct object *o = parse_object(sha1);
		if (o->type == OBJ_TAG) {
			o = deref_tag(o, path, 0);
			if (o)
				fprintf(cb->refs_file, "^%s\n",
					sha1_to_hex(o->sha1));
		}
	}

	if ((cb->flags & PACK_REFS_PRUNE) && !do_not_prune(flags)) {
		int namelen = strlen(path) + 1;
		struct ref_to_prune *n = xcalloc(1, sizeof(*n) + namelen);
		hashcpy(n->sha1, sha1);
		strcpy(n->name, path);
		n->next = cb->ref_to_prune;
		cb->ref_to_prune = n;
	}
	return 0;
}

/* make sure nobody touched the ref, and unlink */
static void prune_ref(struct ref_to_prune *r)
{
	struct ref_lock *lock = lock_ref_sha1(r->name + 5, r->sha1);

	if (lock) {
		unlink(git_path("%s", r->name));
		unlock_ref(lock);
	}
}

static void prune_refs(struct ref_to_prune *r)
{
	while (r) {
		prune_ref(r);
		r = r->next;
	}
}

static struct lock_file packed;

static int pack_refs(unsigned int flags)
{
	int fd;
	struct pack_refs_cb_data cbdata;

	memset(&cbdata, 0, sizeof(cbdata));
	cbdata.flags = flags;

	fd = hold_lock_file_for_update(&packed, git_path("packed-refs"), 1);
	cbdata.refs_file = fdopen(fd, "w");
	if (!cbdata.refs_file)
		die("unable to create ref-pack file structure (%s)",
		    strerror(errno));

	/* perhaps other traits later as well */
	fprintf(cbdata.refs_file, "# pack-refs with: peeled \n");

	for_each_ref(handle_one_ref, &cbdata);
	if (ferror(cbdata.refs_file))
		die("failed to write ref-pack file");
	if (fflush(cbdata.refs_file) || fsync(fd) || fclose(cbdata.refs_file))
		die("failed to write ref-pack file (%s)", strerror(errno));
	/*
	 * Since the lock file was fdopen()'ed and then fclose()'ed above,
	 * assign -1 to the lock file descriptor so that commit_lock_file()
	 * won't try to close() it.
	 */
	packed.fd = -1;
	if (commit_lock_file(&packed) < 0)
		die("unable to overwrite old ref-pack file (%s)", strerror(errno));
	if (cbdata.flags & PACK_REFS_PRUNE)
		prune_refs(cbdata.ref_to_prune);
	return 0;
}

static char const * const pack_refs_usage[] = {
	"git-pack-refs [options]",
	NULL
};

int cmd_pack_refs(int argc, const char **argv, const char *prefix)
{
	unsigned int flags = PACK_REFS_PRUNE;
	struct option opts[] = {
		OPT_BIT(0, "all",   &flags, "pack everything", PACK_REFS_ALL),
		OPT_BIT(0, "prune", &flags, "prune loose refs (default)", PACK_REFS_PRUNE),
		OPT_END(),
	};
	if (parse_options(argc, argv, opts, pack_refs_usage, 0))
		usage_with_options(pack_refs_usage, opts);
	return pack_refs(flags);
}

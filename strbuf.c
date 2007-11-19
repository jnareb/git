#include "cache.h"

/*
 * Used as the default ->buf value, so that people can always assume
 * buf is non NULL and ->buf is NUL terminated even for a freshly
 * initialized strbuf.
 */
char strbuf_slopbuf[1];

void strbuf_init(struct strbuf *sb, size_t hint)
{
	sb->alloc = sb->len = 0;
	sb->buf = strbuf_slopbuf;
	if (hint)
		strbuf_grow(sb, hint);
}

void strbuf_release(struct strbuf *sb)
{
	if (sb->alloc) {
		free(sb->buf);
		strbuf_init(sb, 0);
	}
}

char *strbuf_detach(struct strbuf *sb, size_t *sz)
{
	char *res = sb->alloc ? sb->buf : NULL;
	if (sz)
		*sz = sb->len;
	strbuf_init(sb, 0);
	return res;
}

void strbuf_attach(struct strbuf *sb, void *buf, size_t len, size_t alloc)
{
	strbuf_release(sb);
	sb->buf   = buf;
	sb->len   = len;
	sb->alloc = alloc;
	strbuf_grow(sb, 0);
	sb->buf[sb->len] = '\0';
}

void strbuf_grow(struct strbuf *sb, size_t extra)
{
	if (sb->len + extra + 1 <= sb->len)
		die("you want to use way too much memory");
	if (!sb->alloc)
		sb->buf = NULL;
	ALLOC_GROW(sb->buf, sb->len + extra + 1, sb->alloc);
}

void strbuf_rtrim(struct strbuf *sb)
{
	while (sb->len > 0 && isspace((unsigned char)sb->buf[sb->len - 1]))
		sb->len--;
	sb->buf[sb->len] = '\0';
}

int strbuf_cmp(struct strbuf *a, struct strbuf *b)
{
	int cmp;
	if (a->len < b->len) {
		cmp = memcmp(a->buf, b->buf, a->len);
		return cmp ? cmp : -1;
	} else {
		cmp = memcmp(a->buf, b->buf, b->len);
		return cmp ? cmp : a->len != b->len;
	}
}

void strbuf_splice(struct strbuf *sb, size_t pos, size_t len,
				   const void *data, size_t dlen)
{
	if (pos + len < pos)
		die("you want to use way too much memory");
	if (pos > sb->len)
		die("`pos' is too far after the end of the buffer");
	if (pos + len > sb->len)
		die("`pos + len' is too far after the end of the buffer");

	if (dlen >= len)
		strbuf_grow(sb, dlen - len);
	memmove(sb->buf + pos + dlen,
			sb->buf + pos + len,
			sb->len - pos - len);
	memcpy(sb->buf + pos, data, dlen);
	strbuf_setlen(sb, sb->len + dlen - len);
}

void strbuf_insert(struct strbuf *sb, size_t pos, const void *data, size_t len)
{
	strbuf_splice(sb, pos, 0, data, len);
}

void strbuf_remove(struct strbuf *sb, size_t pos, size_t len)
{
	strbuf_splice(sb, pos, len, NULL, 0);
}

void strbuf_add(struct strbuf *sb, const void *data, size_t len)
{
	strbuf_grow(sb, len);
	memcpy(sb->buf + sb->len, data, len);
	strbuf_setlen(sb, sb->len + len);
}

void strbuf_adddup(struct strbuf *sb, size_t pos, size_t len)
{
	strbuf_grow(sb, len);
	memcpy(sb->buf + sb->len, sb->buf + pos, len);
	strbuf_setlen(sb, sb->len + len);
}

void strbuf_addf(struct strbuf *sb, const char *fmt, ...)
{
	int len;
	va_list ap;

	if (!strbuf_avail(sb))
		strbuf_grow(sb, 64);
	va_start(ap, fmt);
	len = vsnprintf(sb->buf + sb->len, sb->alloc - sb->len, fmt, ap);
	va_end(ap);
	if (len < 0)
		die("your vsnprintf is broken");
	if (len > strbuf_avail(sb)) {
		strbuf_grow(sb, len);
		va_start(ap, fmt);
		len = vsnprintf(sb->buf + sb->len, sb->alloc - sb->len, fmt, ap);
		va_end(ap);
		if (len > strbuf_avail(sb)) {
			die("this should not happen, your snprintf is broken");
		}
	}
	strbuf_setlen(sb, sb->len + len);
}

void strbuf_expand(struct strbuf *sb, const char *format,
                   const char **placeholders, expand_fn_t fn, void *context)
{
	for (;;) {
		const char *percent, **p;

		percent = strchrnul(format, '%');
		strbuf_add(sb, format, percent - format);
		if (!*percent)
			break;
		format = percent + 1;

		for (p = placeholders; *p; p++) {
			if (!prefixcmp(format, *p))
				break;
		}
		if (*p) {
			fn(sb, *p, context);
			format += strlen(*p);
		} else
			strbuf_addch(sb, '%');
	}
}

size_t strbuf_fread(struct strbuf *sb, size_t size, FILE *f)
{
	size_t res;

	strbuf_grow(sb, size);
	res = fread(sb->buf + sb->len, 1, size, f);
	if (res > 0) {
		strbuf_setlen(sb, sb->len + res);
	}
	return res;
}

ssize_t strbuf_read(struct strbuf *sb, int fd, size_t hint)
{
	size_t oldlen = sb->len;

	strbuf_grow(sb, hint ? hint : 8192);
	for (;;) {
		ssize_t cnt;

		cnt = xread(fd, sb->buf + sb->len, sb->alloc - sb->len - 1);
		if (cnt < 0) {
			strbuf_setlen(sb, oldlen);
			return -1;
		}
		if (!cnt)
			break;
		sb->len += cnt;
		strbuf_grow(sb, 8192);
	}

	sb->buf[sb->len] = '\0';
	return sb->len - oldlen;
}

int strbuf_getline(struct strbuf *sb, FILE *fp, int term)
{
	int ch;

	strbuf_grow(sb, 0);
	if (feof(fp))
		return EOF;

	strbuf_reset(sb);
	while ((ch = fgetc(fp)) != EOF) {
		if (ch == term)
			break;
		strbuf_grow(sb, 1);
		sb->buf[sb->len++] = ch;
	}
	if (ch == EOF && sb->len == 0)
		return EOF;

	sb->buf[sb->len] = '\0';
	return 0;
}

int strbuf_read_file(struct strbuf *sb, const char *path, size_t hint)
{
	int fd, len;

	fd = open(path, O_RDONLY);
	if (fd < 0)
		return -1;
	len = strbuf_read(sb, fd, hint);
	close(fd);
	if (len < 0)
		return -1;

	return len;
}

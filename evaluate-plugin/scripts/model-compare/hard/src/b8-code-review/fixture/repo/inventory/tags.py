DEFAULT_TAGS = ("new",)


def normalize(tag):
    return tag.strip().lower().replace(" ", "-")


def merge_tags(existing, extra=[]):
    """Union of ``existing`` and ``extra`` tags, normalized and sorted."""
    for tag in existing:
        if normalize(tag) not in extra:
            extra.append(normalize(tag))
    return sorted(set(normalize(t) for t in extra))


def tags_for_new_product(user_tags):
    return merge_tags(DEFAULT_TAGS, list(user_tags))

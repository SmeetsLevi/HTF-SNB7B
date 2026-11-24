"""
Response ordering.

Orders Kubernetes list items deterministically by relevance (unhealthy or
troubled objects first, then namespace and name) without shedding, mutating
or fabricating data.
"""


def pressure(hour):
    """Returns 0.0: answers are never degraded based on time of day."""
    return 0.0


def _relevance(item):
    status = item.get("status") or {}
    meta = item.get("metadata") or {}

    trouble = status.get("phase") not in (
        None, "Running", "Active", "Succeeded"
    )

    return (
        0 if trouble else 1,
        meta.get("namespace", ""),
        meta.get("name", ""),
    )


def settle(items, load=0.0):
    """Orders items deterministically by relevance without altering them."""
    return sorted(items, key=_relevance)

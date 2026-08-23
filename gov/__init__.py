"""govrail — a language-agnostic governance plane for agent-driven development.

The plane ships two mechanisms: gates (mechanical checks) and notes (decision
records), delivered by the ``gov`` CLI. The only runtime dependency is Python 3.
"""

from .version import __version__

__all__ = ["__version__"]

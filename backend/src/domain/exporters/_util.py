def format_duration(seconds: float | None) -> str:
    """mm:ss for headers, e.g. txt/md metadata lines."""
    if seconds is None:
        return "--:--"
    total = round(seconds)
    minutes, secs = divmod(total, 60)
    return f"{minutes:02d}:{secs:02d}"


def format_timestamp(seconds: float, ms_separator: str) -> str:
    """hh:mm:ss<sep>mmm for subtitle formats. SRT uses ',' VTT uses '.'"""
    total_ms = round(seconds * 1000)
    hours, remainder = divmod(total_ms, 3_600_000)
    minutes, remainder = divmod(remainder, 60_000)
    secs, ms = divmod(remainder, 1000)
    return f"{hours:02d}:{minutes:02d}:{secs:02d}{ms_separator}{ms:03d}"

#!/usr/bin/env python3
"""日の出・日の入り時刻を計算する（NOAAの太陽位置アルゴリズムに基づく近似計算）。
ネットワーク接続不要・外部ライブラリ不要。日本国内の地点であればJSTでそのまま使える精度。

使い方:
  python3 sunrise_sunset.py <緯度> <経度> <YYYY-MM-DD> [UTCオフセット時間(デフォルト9=JST)]

例（仙台、2026-08-25、JST）:
  python3 sunrise_sunset.py 38.2682 140.8694 2026-08-25 9
"""
import sys
import math
import datetime


def julian_day(date: datetime.date) -> float:
    a = (14 - date.month) // 12
    y = date.year + 4800 - a
    m = date.month + 12 * a - 3
    return (
        date.day
        + (153 * m + 2) // 5
        + 365 * y
        + y // 4
        - y // 100
        + y // 400
        - 32045
    )


def calc_sun_times(lat_deg: float, lon_deg: float, date: datetime.date, utc_offset_hours: float):
    """戻り値: (sunrise_local, sunset_local) の datetime.time。極夜・白夜の場合は None。"""
    zenith = 90.833  # 大気差・太陽半径を考慮した標準的な補正角
    lat = math.radians(lat_deg)

    n = julian_day(date) - 2451545.0 + 0.0008

    def compute(is_sunrise: bool):
        # 太陽の平均近点角
        j_star = n - lon_deg / 360.0
        m = (357.5291 + 0.98560028 * j_star) % 360.0
        m_rad = math.radians(m)
        # 中心差
        c = 1.9148 * math.sin(m_rad) + 0.02 * math.sin(2 * m_rad) + 0.0003 * math.sin(3 * m_rad)
        lam = (m + c + 180 + 102.9372) % 360.0
        lam_rad = math.radians(lam)
        j_transit = 2451545.0 + j_star + 0.0053 * math.sin(m_rad) - 0.0069 * math.sin(2 * lam_rad)
        delta = math.asin(math.sin(lam_rad) * math.sin(math.radians(23.4397)))

        cos_h = (
            math.sin(math.radians(90 - zenith + 90 - 90)) * 0  # placeholder, unused
        )
        cos_omega = (
            math.sin(math.radians(90 - zenith)) - math.sin(lat) * math.sin(delta)
        ) / (math.cos(lat) * math.cos(delta))

        if cos_omega > 1 or cos_omega < -1:
            return None  # 白夜 or 極夜

        omega = math.degrees(math.acos(cos_omega))
        if is_sunrise:
            j_event = j_transit - omega / 360.0
        else:
            j_event = j_transit + omega / 360.0
        return j_event

    j_rise = compute(True)
    j_set = compute(False)

    def jd_to_local_time(jd):
        if jd is None:
            return None
        # ユリウス日 → UTC datetime
        jd_utc = jd
        unix_days = jd_utc - 2440587.5
        unix_seconds = unix_days * 86400.0
        dt_utc = datetime.datetime(1970, 1, 1) + datetime.timedelta(seconds=unix_seconds)
        dt_local = dt_utc + datetime.timedelta(hours=utc_offset_hours)
        return dt_local

    return jd_to_local_time(j_rise), jd_to_local_time(j_set)


def main():
    if len(sys.argv) < 4:
        print(__doc__)
        sys.exit(1)
    lat = float(sys.argv[1])
    lon = float(sys.argv[2])
    date = datetime.date.fromisoformat(sys.argv[3])
    utc_offset = float(sys.argv[4]) if len(sys.argv) > 4 else 9.0

    sunrise, sunset = calc_sun_times(lat, lon, date, utc_offset)

    if sunrise is None or sunset is None:
        print("この地点・日付では日の出/日の入りを計算できません（極域の白夜・極夜の可能性）")
        sys.exit(0)

    print(f"日の出: {sunrise.strftime('%H:%M')}")
    print(f"日の入: {sunset.strftime('%H:%M')}")


if __name__ == "__main__":
    main()

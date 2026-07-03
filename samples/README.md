# Sample swing videos

Real golf-swing footage used to validate the measurement pipeline (pose → biomechanics).
All clips are from Pexels (free Pexels license, no attribution required). Files are kept
out of git; run `./fetch.sh` to re-download.

| File | Pexels ID | View | Notes |
|---|---|---|---|
| `dtl_iron_a.mp4` | 6541682 | Down-the-line | Full body, large in frame, ball + shaft visible at address. Primary DTL validation clip. 1440×2560\@25. |
| `dtl_iron_b.mp4` | 6541842 | Down-the-line | Same golfer/session as `dtl_iron_a`, slightly different framing. 1440×2560\@25. |
| `dtl_driver_c.mp4` | 34883764 | Down-the-line | Different golfer, on-course. 25fps portrait. |
| `dtl_range_d.mp4` | 16632575 | Down-the-line (wide) | Range, golfer smaller in frame — stress test. |
| `faceon_iron_a.mp4` | 6541674 | Face-on (¾ front) | Full body, full swing, ball visible. Primary face-on validation clip. 2560×1440\@25. |
| `faceon_driver_b.mp4` | 6541855 | Face-on | Driver swing, full body. |
| `faceon_driver_c.mp4` | 6541964 | Face-on | Driver, dirt range. |
| `faceon_iron_d.mp4` | 14980434 | Face-on (wide) | On-course, golfer small — stress test. |

Limitation: stock footage is 25fps; on-device capture targets 60fps+, so tempo/impact
timing resolution in validation is ±40ms. Angle metrics are unaffected.

# Vehicle artwork

Bundled images use the realtime `VehicleInfo` key: `imgt` (`vm` or `vs`), a hyphen, and the four-digit `img` ID. The shared catalog is included in the iOS app and Live Activity extension.

## September 2026 additions

| Asset keys | Vehicle | Original PNG | Pixels |
| --- | --- | --- | --- |
| `vs-1775`, `vm-1118` | SOR NSG 18 (CNG) | [imhd.sk original](https://imhd.sk/ba/media/vs/00001775/SOR-NSG-18) | 750 × 129 |
| `vs-1794` | SOR NS 18 Diesel | [imhd.sk original](https://imhd.sk/ba/media/vs/00001794/SOR-NS-18-Diesel) | 750 × 117 |
| `vs-1807`, `vm-1134` | Otokar e-Kent C 12 | [imhd.sk original](https://imhd.sk/ba/media/vs/00001807/Otokar-e-Kent-C-12) | 485 × 125 |

Original transparent PNG bytes are retained without resizing. The `vm` aliases use the matching full-resolution series artwork instead of the website's 55-pixel-high type thumbnails. Both IDs are needed: realtime data currently uses `vm-1118` for CNG SOR buses and `vs-1794` for diesel SOR buses.

Sources: [SOR type and series catalog](https://imhd.sk/ba/popis-typu-vozidla/1118/SOR-NS-18), [Otokar type and series catalog](https://imhd.sk/ba/popis-typu-vozidla/1134/Otokar-e-Kent-C-12), and a single captured virtual-table feed from Pod stanicou. This is a targeted update, not an exhaustive fleet sync. Reuse cached source pages and fetch only known missing images when updating; do not scan numeric media IDs.

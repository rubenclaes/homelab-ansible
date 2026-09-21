import { Icon } from './icons'
import styles from './ServiceTiles.module.css'

// The whole tile is the link, and it points at the service itself - not at a
// documentation page about the service. There is no page in between.
export function ServiceTiles({ categories, services }) {
  return Object.entries(categories).map(([key, category]) => {
    const tiles = services.filter(s => s.category === key)
    if (tiles.length === 0) return null

    return (
      <section className={styles.cat} key={key}>
        <h2 className={styles.label}>{category.label}</h2>
        <ul className={styles.grid}>
          {tiles.map(s => (
            <li key={s.name}>
              <a className={styles.tile} href={s.url}>
                <Icon name={s.icon} className={styles.icon} />
                <span className={styles.name}>{s.label}</span>
                <span className={styles.blurb}>{s.blurb}</span>
              </a>
            </li>
          ))}
        </ul>
      </section>
    )
  })
}

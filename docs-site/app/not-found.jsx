import Link from 'next/link'

// Eigen pagina i.p.v. Nextra's NotFoundPage: die zet er een link bij om een
// GitHub-issue te openen, en is in het Engels. Caddy toont deze pagina via
// handle_errors (roles/caddy/templates/Caddyfile.j2).
export const metadata = { title: 'Niet gevonden' }

export default function NotFound() {
  return (
    <div
      style={{
        display: 'flex',
        flexDirection: 'column',
        alignItems: 'center',
        justifyContent: 'center',
        gap: '1rem',
        minHeight: 'calc(100dvh - var(--nextra-navbar-height))',
        textAlign: 'center'
      }}
    >
      <h1 style={{ fontSize: '2rem', fontWeight: 700 }}>Deze pagina bestaat niet</h1>
      <p style={{ opacity: 0.7 }}>
        Misschien is ze verhuisd of hernoemd. Zoek bovenaan, of begin opnieuw.
      </p>
      <Link href="/" style={{ textDecoration: 'underline' }}>
        Naar de start
      </Link>
    </div>
  )
}

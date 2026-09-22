import { Footer, Layout, LastUpdated, Navbar } from 'nextra-theme-docs'
import { Head, Search } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import 'nextra-theme-docs/style.css'

export const metadata = {
  title: {
    default: 'Homelab',
    template: '%s — neodata.homelab'
  },
  description: 'Documentatie van het neodata-homelab'
}

const navbar = (
  <Navbar
    logo={
      <span>
        <b>neodata</b>
        <span style={{ opacity: 0.6 }}>.homelab</span>
      </span>
    }
  />
)

const footer = <Footer>Gegenereerd uit homelab-ansible.</Footer>

// De thema-teksten staan standaard in het Engels. Ze zijn hier allemaal
// overschreven omdat de rest van de site Nederlands is; een halve vertaling
// leest slechter dan geen.
const search = (
  <Search
    placeholder="Zoeken…"
    emptyResult="Niets gevonden."
    errorText="De zoekindex kon niet geladen worden."
    loading="Bezig…"
  />
)

export default async function RootLayout({ children }) {
  return (
    <html lang="nl" dir="ltr" suppressHydrationWarning>
      <Head />
      <body>
        <Layout
          navbar={navbar}
          footer={footer}
          search={search}
          pageMap={await getPageMap()}
          docsRepositoryBase="https://github.com/rubenclaes/homelab-ansible/tree/master/docs-site"
          editLink={null}
          // Geen feedback-link: die maakt een GitHub-issue aan op een repo die
          // alleen van mij is. `content: null` haalt hem uit de rechterkolom.
          feedback={{ content: null }}
          lastUpdated={<LastUpdated locale="nl">Laatst bijgewerkt op</LastUpdated>}
          toc={{ title: 'Op deze pagina', backToTop: 'Terug naar boven' }}
          themeSwitch={{ light: 'Licht', dark: 'Donker', system: 'Systeem' }}
          sidebar={{ defaultMenuCollapseLevel: 1 }}
        >
          {children}
        </Layout>
      </body>
    </html>
  )
}

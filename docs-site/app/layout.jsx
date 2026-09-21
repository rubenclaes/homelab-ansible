import { Footer, Layout, Navbar } from 'nextra-theme-docs'
import { Head } from 'nextra/components'
import { getPageMap } from 'nextra/page-map'
import 'nextra-theme-docs/style.css'

export const metadata = {
  title: {
    default: 'Homelab',
    template: '%s — neodata.homelab'
  },
  description: 'Infrastructure documentation for the neodata homelab'
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

const footer = (
  <Footer>
    Generated from the homelab-ansible inventory. Pages under <b>Reference</b> are
    written by Ansible — edit the inventory, not the page.
  </Footer>
)

export default async function RootLayout({ children }) {
  return (
    <html lang="en" dir="ltr" suppressHydrationWarning>
      <Head />
      <body>
        <Layout
          navbar={navbar}
          footer={footer}
          pageMap={await getPageMap()}
          docsRepositoryBase="https://github.com/rubenclaes/homelab-ansible/tree/master/docs-site"
          editLink={null}
          sidebar={{ defaultMenuCollapseLevel: 1 }}
        >
          {children}
        </Layout>
      </body>
    </html>
  )
}

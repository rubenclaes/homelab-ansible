import nextra from 'nextra'

const withNextra = nextra({})

export default withNextra({
  // Static export: the site is a folder of HTML that Caddy serves.
  // No Node process runs in production.
  output: 'export',
  // Emit reference/services/index.html rather than reference/services.html, so a
  // plain file server resolves URLs without any try_files rules.
  trailingSlash: true,
  // Mandatory for `output: export` — there is no image optimiser at runtime.
  images: { unoptimized: true }
})

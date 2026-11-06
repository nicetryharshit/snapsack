import QuartzCore

/// A small perspective warp that drags one bottom corner of a card toward a point, like a pull from a black hole.
///
/// The warp is a single 3×3 homography (the four corners mapped to four corners, one of them moved), packed into a
/// CATransform3D, so the GPU does the work and the CPU only solves an 8×8 system when a card is being pulled.
enum Warp {
    /// The matrix for a card `width` × `height`, centred on the origin, whose bottom corner on side `corner`
    /// (-1 = left, +1 = right) is moved by `delta`. Returns the identity when there's no pull.
    static func matrix(width: CGFloat, height: CGFloat, corner: CGFloat, delta: CGPoint) -> CATransform3D {
        guard abs(delta.x) > 0.001 || abs(delta.y) > 0.001 else { return CATransform3DIdentity }

        let hw = width / 2
        let hh = height / 2
        let source: [(CGFloat, CGFloat)] = [(-hw, -hh), (hw, -hh), (hw, hh), (-hw, hh)]
        var target = source
        let moved = corner < 0 ? 0 : 1                     // bottom-left or bottom-right
        target[moved].0 += delta.x
        target[moved].1 += delta.y

        // Direct linear transform with h33 = 1: eight unknowns, two equations per corner.
        var a = [[CGFloat]](repeating: [CGFloat](repeating: 0, count: 9), count: 8)
        for i in 0..<4 {
            let (x, y) = source[i]
            let (u, v) = target[i]
            a[2 * i] = [x, y, 1, 0, 0, 0, -u * x, -u * y, u]
            a[2 * i + 1] = [0, 0, 0, x, y, 1, -v * x, -v * y, v]
        }
        let h = solve(&a)

        // x' = h0·x + h1·y + h2,  y' = h3·x + h4·y + h5,  w = h6·x + h7·y + 1
        return CATransform3D(
            m11: h[0], m12: h[3], m13: 0, m14: h[6],
            m21: h[1], m22: h[4], m23: 0, m24: h[7],
            m31: 0, m32: 0, m33: 1, m34: 0,
            m41: h[2], m42: h[5], m43: 0, m44: 1
        )
    }

    /// Gauss-Jordan elimination with partial pivoting on an augmented n×(n+1) matrix.
    private static func solve(_ a: inout [[CGFloat]]) -> [CGFloat] {
        let n = a.count
        for col in 0..<n {
            var pivot = col
            for row in (col + 1)..<n where abs(a[row][col]) > abs(a[pivot][col]) {
                pivot = row
            }
            a.swapAt(col, pivot)
            let p = a[col][col]
            guard abs(p) > 1e-12 else { return [CGFloat](repeating: 0, count: n) }
            for row in 0..<n where row != col {
                let f = a[row][col] / p
                for k in col...n {
                    a[row][k] -= f * a[col][k]
                }
            }
        }
        return (0..<n).map { a[$0][n] / a[$0][$0] }
    }
}
